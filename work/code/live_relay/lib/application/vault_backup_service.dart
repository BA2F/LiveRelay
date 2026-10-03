import 'dart:convert';
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
    final key = await _session.authenticatePassword(password);
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
      importedKey = await stagedKeyManager.unlock(
        _session.canonicalizePassword(backupPassword, metadata),
      );
      await _archiveService.verifyAuthentication(
        staged: staged,
        masterKey: importedKey,
      );
      await stagedKeyManager.setBiometricEnabled(false);
      final testDatabase = await _session.openTemporary(
        staged.directory,
        importedKey,
      );
      await testDatabase.close();

      await _session.close();
      clearUnlockedData();
      transactionStarted = true;
      try {
        recoveryNotice = await _restoreTransaction.install(
          staged.directory,
          verifyInstalled: () async {
            await _session.openWithKey(importedKey!);
            await _session.reloadHeader();
            await refreshUnlockedData();
          },
          closeInstalled: () async {
            await _session.close();
            clearUnlockedData();
          },
        );
        _session.markUnlocked();
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
      key = await manager.unlock(
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

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
