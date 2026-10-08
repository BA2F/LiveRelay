import 'dart:io';
import 'dart:convert';

import 'dart:async';
import 'dart:typed_data';

import 'package:collection/collection.dart';

import '../core/security/owner_crypto.dart';
import '../core/security/recovery_credential.dart';
import '../core/security/vault_header_v3.dart';
import '../core/security/vault_header_metadata.dart';
import '../core/ports/vault_installation.dart';
import '../core/ports/vault_maintenance.dart';

class VaultSecurityProgress {
  const VaultSecurityProgress(this.busy, this.stage);
  final bool busy;
  final String stage;
}

class VaultSecurityService {
  VaultSecurityService(this.session, this.createTransaction);
  final VaultMaintenance session;
  final VaultInstallation Function() createTransaction;
  late final transaction = createTransaction();
  String _stageText = '';
  bool _busy = false;
  bool _disposed = false;
  String get stage => _stageText;
  bool get busy => _busy;
  final _changes = StreamController<VaultSecurityProgress>.broadcast();
  Stream<VaultSecurityProgress> get changes => _changes.stream;
  void _changed() {
    if (!_disposed) _changes.add(VaultSecurityProgress(busy, stage));
  }

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
  }

  void _checkEpoch(int epoch) {
    if (_disposed || epoch != session.operationEpoch) {
      throw StateError('安全更新已取消');
    }
  }

  void _stage(String value) {
    _stageText = value;
    _changed();
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
  }) => session.exclusiveMaintenance(
    () => _configure(
      oldPassword: oldPassword,
      newPassword: newPassword,
      recoveryText: recoveryText,
      recoveryConfirmation: recoveryConfirmation,
      policy: policy,
      oldKeyFile: oldKeyFile,
      newKeyFile: newKeyFile,
      biometric: biometric,
      chinese: chinese,
      wordCount: wordCount,
    ),
  );

  Future<void> _configure({
    required String oldPassword,
    required String newPassword,
    required String recoveryText,
    required String recoveryConfirmation,
    required String policy,
    Uint8List? oldKeyFile,
    Uint8List? newKeyFile,
    required bool biometric,
    required bool chinese,
    int? wordCount,
  }) async {
    if (_disposed) throw StateError('安全服务已销毁');
    if (busy) throw StateError('安全更新正在进行');
    if (recoveryText != recoveryConfirmation) {
      throw const FormatException('请完整回输恢复凭证确认');
    }
    final startingEpoch = session.operationEpoch;
    final recovery = await RecoveryCredential.parse(recoveryText);
    _busy = true;
    _changed();
    Directory? staging;
    Uint8List? snapshot;
    final nextKey = OwnerCrypto.random(32);
    VaultHeaderV3? candidate;
    var committed = false;
    try {
      _checkEpoch(startingEpoch);
      await session.withMasterKey((oldKey) async {
        final epoch = session.operationEpoch;
        if (session.state != VaultSessionState.recovering) {
          final proof = await session.authenticateDaily(
            oldPassword,
            keyFile: oldKeyFile,
          );
          try {
            if (!const ListEquality<int>().equals(proof, oldKey)) {
              throw StateError('当前会话已变化');
            }
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
        await session.writeStagedHeader(staging!, candidate!);
        final target = await session.openTemporary(staging!, nextKey);
        try {
          await target.importLocalState(snapshot!);
        } finally {
          try {
            await target.close();
          } finally {
            OwnerCrypto.wipe(snapshot);
            snapshot = null;
          }
        }
        for (var i = 0; i < blobs.length; i++) {
          _checkEpoch(epoch);
          _stage('重新加密原件 ${i + 1}/${blobs.length}');
          if (missing.containsKey(blobs[i].relativePath)) continue;
          await session.copyBlobUnderKey(
            target: staging!,
            oldKey: oldKey,
            newKey: nextKey,
            blob: blobs[i],
          );
        }
        _checkEpoch(epoch);
        _stage('核验并提交新资料库');
        await session.close();
        final installingEpoch = session.operationEpoch;
        await transaction.install(
          staging!,
          verifyInstalled: () async {
            _checkEpoch(installingEpoch);
            await session.openWithKey(nextKey);
            await session.reloadHeader();
            _checkEpoch(installingEpoch);
            for (final blob in blobs) {
              if (missing.containsKey(blob.relativePath)) continue;
              final clear = await session.readOriginal(blob);
              OwnerCrypto.wipe(clear);
              _checkEpoch(installingEpoch);
            }
          },
          closeInstalled: session.close,
        );
        committed = true;
        _checkEpoch(installingEpoch);
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
      try {
        if (staging != null && await staging!.exists()) {
          await staging!.delete(recursive: true);
        }
      } finally {
        OwnerCrypto.wipe(snapshot);
        OwnerCrypto.wipe(nextKey);
        recovery.dispose();
        _busy = false;
        _stageText = '';
        _changed();
      }
    }
  }
}
