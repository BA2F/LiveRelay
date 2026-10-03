import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';

import '../core/security/header_encoding.dart';
import '../core/security/owner_crypto.dart';

import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../core/domain/entities.dart';
import '../core/ports/vault_repository.dart';
import '../core/security/vault_key_manager.dart';
import '../infrastructure/backup/life_vault_archive.dart';
import '../infrastructure/backup/vault_restore_transaction.dart';
import 'vault_session.dart';

/// Coordinates authenticated archives and K0 installation. UI callbacks only
/// clear or reload projections; they never receive keys, files or repositories.
class VaultBackupService {
  VaultBackupService({
    required this._session,
    required LifeVaultArchiveService archive,
    required VaultRestoreTransaction Function() restoreTransaction,
  }) : _archiveService = archive,
       _createRestoreTransaction = restoreTransaction;

  final VaultSession _session;
  final LifeVaultArchiveService _archiveService;
  final VaultRestoreTransaction Function() _createRestoreTransaction;
  late final VaultRestoreTransaction _restoreTransaction =
      _createRestoreTransaction();
  String? recoveryNotice;

  Future<void> recover() async {
    recoveryNotice = await _restoreTransaction.recover();
  }

  Future<Uint8List> export(
    String password, {
    required Future<void> Function() refreshUnlockedData,
  }) async {
    if (!_session.isUnlocked) throw StateError('请先解锁加密资料库');
    if (await missingCount() > 0) throw StateError('请先补齐原件再导出完整备份');
    final key = password.startsWith('LRR1')
        ? await _session.authenticateRecovery(password)
        : await _session.authenticateDaily(password);
    try {
      await _session.suspendDatabase();
      return await _archiveService.create(
        vaultDirectory: _session.directory,
        masterKey: key,
      );
    } finally {
      try {
        await _session.openWithKey(key);
        await refreshUnlockedData();
      } finally {
        _wipe(key);
      }
    }
  }

  Future<void> restore(
    Uint8List bytes,
    String backupPassword, {
    required void Function() clearUnlockedData,
    required Future<void> Function() refreshUnlockedData,
  }) async {
    StagedLifeVault? staged;
    Uint8List? importedKey;
    var transactionStarted = false;
    try {
      await _session.directory.parent.create(recursive: true);
      staged = await _archiveService.stage(
        archiveBytes: bytes,
        stagingParent: _session.directory.parent,
      );
      final stagedKeyManager = VaultKeyManager(staged.directory);
      final metadata = await stagedKeyManager.readMetadata();
      if (metadata == null) {
        throw const LifeVaultArchiveException('.lvault 缺少 Vault header');
      }
      if (staged.kind == 'attachments') {
        throw const LifeVaultArchiveException('请选择数据库或完整备份；原件包应在解锁后导入');
      }
      importedKey = backupPassword.startsWith('LRR1')
          ? await stagedKeyManager.unlockWithRecovery(backupPassword)
          : await stagedKeyManager.unlock(
              _session.canonicalizePassword(backupPassword, metadata),
            );
      await _archiveService.verifyAuthentication(
        staged: staged,
        masterKey: importedKey,
      );
      if (metadata.formatVersion == 1) {
        await stagedKeyManager.setBiometricEnabled(false);
      }
      final testDatabase = await _session.openTemporary(
        staged.directory,
        importedKey,
      );
      try {
        if (staged.omitted.isNotEmpty) {
          final missing = <String, Object?>{};
          final blobs = await testDatabase.listBlobs();
          for (final entry in staged.omitted.entries) {
            if (!blobs.any((b) => b.relativePath == entry.key)) {
              throw const LifeVaultArchiveException('缺失原件不属于数据库');
            }
            missing[entry.key] = {
              ...(entry.value as Map),
              'key': base64UrlEncode(importedKey),
              'snapshotId': staged.snapshotId,
            };
          }
          await testDatabase.writeLocalValue(
            'backup.missing',
            jsonEncode(missing),
          );
        }
      } finally {
        await testDatabase.close();
      }

      await _session.close();
      clearUnlockedData();
      transactionStarted = true;
      try {
        recoveryNotice = await _restoreTransaction.install(
          staged.directory,
          verifyInstalled: () async {
            await _session.openWithKey(importedKey!);
            await _session.reloadHeader();
            if (metadata.formatVersion == 1) await refreshUnlockedData();
          },
          closeInstalled: () async {
            await _session.close();
            clearUnlockedData();
          },
        );
        if (metadata.formatVersion == 3) {
          _session.markRecovering();
        } else {
          _session.markUnlocked();
        }
        await _session.clearDeviceKeyAfterRestore();
      } on Object {
        await _session.close();
        clearUnlockedData();
        try {
          recoveryNotice = await _restoreTransaction.recover();
          await _session.inspectRecoveredHeader();
        } on Object {
          _session.fail();
          throw const VaultRecoveryException();
        }
        throw const LifeVaultArchiveException('恢复未完成；资料库已保留，请使用对应密码重新解锁');
      }
    } finally {
      if (!transactionStarted &&
          staged != null &&
          await staged.directory.exists()) {
        await staged.directory.delete(recursive: true);
      }
      if (importedKey != null) _wipe(importedKey);
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<BackupPreview> inspect(Uint8List bytes, String password) async {
    await _session.directory.parent.create(recursive: true);
    final staged = await _archiveService.stage(
      archiveBytes: bytes,
      stagingParent: _session.directory.parent,
    );
    Uint8List? key;
    VaultRepository? repository;
    try {
      final manager = VaultKeyManager(staged.directory);
      final metadata = await manager.readMetadata();
      if (metadata == null) throw const LifeVaultArchiveException('备份缺少资料库头');
      if (staged.kind == 'attachments') {
        throw const LifeVaultArchiveException('原件补充包不能单独恢复资料库');
      }
      key = password.startsWith('LRR1')
          ? await manager.unlockWithRecovery(password)
          : await manager.unlock(
              _session.canonicalizePassword(password, metadata),
            );
      await _archiveService.verifyAuthentication(
        staged: staged,
        masterKey: key,
      );
      final r = await _session.openTemporary(staged.directory, key);
      repository = r;
      final archive = ZipDecoder().decodeBytes(bytes);
      final container = jsonDecode(
        utf8.decode(archive.findFile('container.json')!.readBytes()!),
      ) as Map;
      return BackupPreview(
        missingOriginals: staged.omitted.length,
        requiresReset: metadata.formatVersion == 3,
        createdAt: DateTime.tryParse('${container['createdAt']}'),
        cards: (await r.listCards()).length,
        credentials: (await r.listCredentials()).length,
        originals: (await r.listBlobs()).length,
        recycledCards: (await r.listCards(recycled: true)).length,
        recycledCredentials: (await r.listCredentials(recycled: true)).length,
      );
    } finally {
      await repository?.close();
      if (key != null) _wipe(key);
      if (await staged.directory.exists()) {
        await staged.directory.delete(recursive: true);
      }
    }
  }

  Future<({Uint8List database, Uint8List attachments})> exportSplit(
    String credential,
    Future<void> Function() refresh,
  ) async {
    if (!_session.isUnlocked) throw StateError('请先解锁');
    if (await missingCount() > 0) throw StateError('请先补齐原件再导出新的分层备份');
    final key = credential.startsWith('LRR1')
        ? await _session.authenticateRecovery(credential)
        : await _session.authenticateDaily(credential);
    final snapshot = HeaderEncoding.hex(OwnerCrypto.random(16));
    try {
      await _session.suspendDatabase();
      final database = await _archiveService.create(
        vaultDirectory: _session.directory,
        masterKey: key,
        kind: 'database',
        snapshotId: snapshot,
      );
      try {
        final attachments = await _archiveService.create(
          vaultDirectory: _session.directory,
          masterKey: key,
          kind: 'attachments',
          snapshotId: snapshot,
        );
        return (database: database, attachments: attachments);
      } catch (_) {
        _wipe(database);
        rethrow;
      }
    } finally {
      try {
        await _session.openWithKey(key);
        await refresh();
      } finally {
        _wipe(key);
      }
    }
  }

  Future<int> missingCount() async {
    if (!_session.isUnlocked) return 0;
    final value = await _session.repository.readLocalValue('backup.missing');
    return value == null ? 0 : (jsonDecode(value) as Map).length;
  }

  Future<void> importSupplement(Uint8List bytes) async {
    if (!_session.isUnlocked) throw StateError('请先解锁');
    final epoch = _session.operationEpoch;
    final value = await _session.repository.readLocalValue('backup.missing');
    if (value == null || (jsonDecode(value) as Map).isEmpty) {
      throw StateError('当前没有待恢复原件');
    }
    final missing = Map<String, Object?>.from(jsonDecode(value) as Map);
    final staged = await _archiveService.stage(
      archiveBytes: bytes,
      stagingParent: _session.directory.parent,
    );
    try {
      if (staged.kind != 'attachments') throw StateError('请选择原件补充包');
      final metadata = await _session.repository.listBlobs();
      await _session.withMasterKey((currentKey) async {
        final expected = missing.values.first as Map;
        final oldKey = Uint8List.fromList(
          base64Url.decode(expected['key'] as String),
        );
        try {
          await _archiveService.verifyAuthentication(
            staged: staged,
            masterKey: oldKey,
          );
          if (staged.snapshotId != expected['snapshotId']) {
            throw StateError('此原件包与数据库备份不配对');
          }
          final store = _session.blobStore;
          for (final entry in missing.entries.toList()) {
            if (epoch != _session.operationEpoch) throw StateError('导入已取消');
            final descriptor = entry.value as Map;
            final file = File('${staged.directory.path}/${entry.key}');
            if (!await file.exists()) throw StateError('原件包缺少预期文件');
            final cipher = await file.readAsBytes();
            if (cipher.length != descriptor['size'] ||
                base64UrlEncode((await Sha256().hash(cipher)).bytes) !=
                    descriptor['sha256']) {
              throw StateError('原件与数据库备份不匹配');
            }
            final blob = metadata.singleWhere(
              (b) => b.relativePath == entry.key,
            );
            await store.copyUnderKey(
              source: staged.directory,
              target: _session.directory,
              oldKey: oldKey,
              newKey: currentKey,
              blob: blob,
            );
            if (epoch != _session.operationEpoch) throw StateError('导入已取消');
            missing.remove(entry.key);
            await _session.repository.writeLocalValue(
              'backup.missing',
              jsonEncode(missing),
            );
          }
        } finally {
          _wipe(oldKey);
        }
      });
    } finally {
      if (await staged.directory.exists()) {
        await staged.directory.delete(recursive: true);
      }
      _wipe(bytes);
    }
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
