import 'dart:io';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/security/owner_crypto.dart';
import '../core/security/recovery_credential.dart';
import '../core/security/vault_header_v3.dart';
import '../core/security/vault_key_manager.dart';
import '../infrastructure/backup/vault_restore_transaction.dart';
import 'vault_session.dart';

class VaultSecurityService extends ChangeNotifier {
  VaultSecurityService(this.session, this.createTransaction);
  final VaultSession session;
  final VaultRestoreTransaction Function() createTransaction;
  late final transaction = createTransaction();
  String stage = '';
  bool busy = false;
  void _stage(String value) {
    stage = value;
    notifyListeners();
  }

  Future<void> configure({
    required String oldPassword,
    required String newPassword,
    required String recoveryText,
    required String recoveryConfirmation,
    String policy = 'any',
    Uint8List? oldKeyFile,
    Uint8List? newKeyFile,
    bool biometric = false,
    bool chinese = false,
    int? wordCount,
  }) async {
    if (busy) throw StateError('安全更新正在进行');
    if (recoveryText != recoveryConfirmation) {
      throw const FormatException('请完整回输恢复凭证确认');
    }
    final recovery = await RecoveryCredential.parse(recoveryText);
    busy = true;
    notifyListeners();
    Directory? staging;
    Uint8List? snapshot;
    final nextKey = OwnerCrypto.random(32);
    VaultHeaderV3? candidate;
    var committed = false;
    try {
      await session.withMasterKey((oldKey) async {
        final epoch = session.operationEpoch;
        if (session.state != VaultSessionState.recovering) {
          final proof = await session.authenticateDaily(
            oldPassword,
            keyFile: oldKeyFile,
          );
          try {
            if (!listEquals(proof, oldKey)) throw StateError('当前会话已变化');
          } finally {
            OwnerCrypto.wipe(proof);
          }
        }
        _stage('重新封装解锁凭证');
        final previous = await session.modernHeader();
        final canonical = chinese
            ? session.canonicalizePassword(
                newPassword,
                VaultHeaderMetadata(
                  passwordKind: 'diceware-cn-v1',
                  wordCount: wordCount,
                  biometricEnabled: false,
                  createdAt: DateTime.now(),
                ),
              )
            : newPassword;
        candidate = await VaultHeaderV3.create(
          password: canonical,
          masterKey: nextKey,
          recovery: recovery,
          passwordKind: chinese ? 'diceware-cn-v1' : 'custom',
          wordCount: chinese ? wordCount : null,
          policy: policy,
          keyFile: newKeyFile,
          device: biometric ? session.deviceProtection : null,
          vaultId: previous?.vaultId,
          epoch: (previous?.epoch ?? 0) + 1,
          generation: (previous?.generation ?? 0) + 1,
          createdAt: session.header?.createdAt,
        );
        _stage('准备加密数据库副本');
        snapshot = await session.repository.exportLocalState();
        final blobs = await session.repository.listBlobs();
        final missingText = await session.repository.readLocalValue(
          'backup.missing',
        );
        final missing = missingText == null
            ? <String, Object?>{}
            : Map<String, Object?>.from(jsonDecode(missingText) as Map);
        await session.directory.parent.create(recursive: true);
        staging = await session.directory.parent.createTemp(
          'liverelay-restore-',
        );
        await VaultKeyManager(staging!).writeV3(candidate!);
        final target = await session.openTemporary(staging!, nextKey);
        try {
          await target.importLocalState(snapshot!);
        } finally {
          await target.close();
          OwnerCrypto.wipe(snapshot);
          snapshot = null;
        }
        for (var i = 0; i < blobs.length; i++) {
          if (epoch != session.operationEpoch) throw StateError('安全更新已取消');
          _stage('重新加密原件 ${i + 1}/${blobs.length}');
          if (missing.containsKey(blobs[i].relativePath)) continue;
          await session.copyBlobUnderKey(
            target: staging!,
            oldKey: oldKey,
            newKey: nextKey,
            blob: blobs[i],
          );
        }
        if (epoch != session.operationEpoch) throw StateError('安全更新已取消');
        _stage('核验并提交新资料库');
        await session.close();
        final installingEpoch = session.operationEpoch;
        await transaction.install(
          staging!,
          verifyInstalled: () async {
            if (installingEpoch != session.operationEpoch) {
              throw StateError('安全更新已取消');
            }
            await session.openWithKey(nextKey);
            await session.reloadHeader();
            if (installingEpoch != session.operationEpoch) {
              throw StateError('安全更新已取消');
            }
            for (final blob in blobs) {
              if (missing.containsKey(blob.relativePath)) continue;
              final clear = await session.readOriginal(blob);
              OwnerCrypto.wipe(clear);
            }
          },
          closeInstalled: session.close,
        );
        committed = true;
        session.markUnlocked();
        await session.clearDeviceKeyAfterRestore();
        for (final ref in previous?.deviceReferences ?? <String>[]) {
          try {
            await session.deviceProtection?.deleteFactor(ref);
          } on Object {
            /* no old namespace read */
          }
        }
      });
    } on Object {
      if (!committed) {
        await session.close();
        try {
          await transaction.recover();
          await session.inspectRecoveredHeader();
        } on Object {
          session.fail();
        }
      }
      rethrow;
    } finally {
      if (!committed) {
        for (final ref in candidate?.deviceReferences ?? <String>[]) {
          try {
            await session.deviceProtection?.deleteFactor(ref);
          } on Object {
            /* orphan cleanup */
          }
        }
      }
      if (staging != null && await staging!.exists()) {
        await staging!.delete(recursive: true);
      }
      OwnerCrypto.wipe(snapshot);
      OwnerCrypto.wipe(nextKey);
      recovery.dispose();
      busy = false;
      stage = '';
      notifyListeners();
    }
  }
}
