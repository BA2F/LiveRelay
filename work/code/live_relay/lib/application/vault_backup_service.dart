import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';

import '../core/security/vault_archive_identity.dart';

import 'dart:typed_data';

import '../core/domain/entities.dart';
import '../core/ports/vault_repository.dart';
import '../core/ports/vault_archive.dart';
import '../core/ports/vault_installation.dart';
import '../core/ports/vault_maintenance.dart';
import '../core/storage/vault_failures.dart';
import 'vault_snapshot_query.dart';

/// Result of installing an archive: how many originals were reused from the
/// vault being replaced, and how the session was left afterwards.
class RestoreOutcome {
  const RestoreOutcome({
    required this.harvestedOriginals,
    required this.requiresReset,
    required this.unlockedAfterRestore,
  });

  final int harvestedOriginals;
  final bool requiresReset;
  final bool unlockedAfterRestore;
}

/// Coordinates authenticated archives and K0 installation. UI callbacks only
/// clear or reload projections; they never receive keys, files or repositories.
class VaultBackupService {
  VaultBackupService({
    required this._session,
    required VaultArchive archive,
    required VaultInstallation Function() restoreTransaction,
  }) : _archiveService = archive,
       _createRestoreTransaction = restoreTransaction;

  final VaultMaintenance _session;
  final VaultArchive _archiveService;
  final VaultInstallation Function() _createRestoreTransaction;
  late final VaultInstallation _restoreTransaction =
      _createRestoreTransaction();
  String? recoveryNotice;

  Future<void> recover() => _session.exclusiveMaintenance(() async {
    recoveryNotice = await _restoreTransaction.recover();
  });

  Future<Uint8List> export(
    String password, {
    required Future<void> Function() refreshUnlockedData,
  }) => _session.exclusiveMaintenance(
    () => _exportAuthenticated(
      password,
      refreshUnlockedData,
      (key) => _archiveService.create(
        vaultDirectory: _session.directory,
        masterKey: key,
      ),
      _wipe,
    ),
  );

  /// Never reopen a locked/disposed session from an export's late finally.
  /// If reopening/refresh fails, a produced result is withheld and discarded.
  Future<T> _exportAuthenticated<T>(
    String credential,
    Future<void> Function() refresh,
    Future<T> Function(Uint8List key) create,
    void Function(T value) discard,
  ) async {
    if (!_session.isUnlocked) throw StateError('请先解锁加密资料库');
    final epoch = _session.operationEpoch;
    if (await missingCount() > 0) throw StateError('请先补齐原件再导出备份');
    _checkEpoch(epoch);
    final key = credential.startsWith('LRR1')
        ? await _session.authenticateRecovery(credential)
        : await _session.authenticateDaily(credential);
    T? result;
    try {
      _checkEpoch(epoch);
      try {
        await _session.suspendDatabase();
        _checkEpoch(epoch);
        result = await create(key);
        _checkEpoch(epoch);
      } finally {
        if (epoch == _session.operationEpoch) {
          await _session.openWithKey(key);
          _checkEpoch(epoch);
          await refresh();
          _checkEpoch(epoch);
        }
      }
      return result as T;
    } on Object {
      if (result != null) discard(result);
      rethrow;
    } finally {
      _wipe(key);
    }
  }

  Future<RestoreOutcome> restore(
    Uint8List bytes,
    String backupPassword, {
    required void Function() clearUnlockedData,
    required Future<void> Function() refreshUnlockedData,
  }) => _consumeInput(
    bytes,
    () => _session.exclusiveMaintenance(
      () => _restore(
        bytes,
        backupPassword,
        clearUnlockedData: clearUnlockedData,
        refreshUnlockedData: refreshUnlockedData,
      ),
    ),
  );

  Future<RestoreOutcome> _restore(
    Uint8List bytes,
    String backupPassword, {
    required void Function() clearUnlockedData,
    required Future<void> Function() refreshUnlockedData,
  }) async {
    final epoch = _session.operationEpoch;
    StagedLifeVault? staged;
    Uint8List? importedKey;
    var transactionStarted = false;
    try {
      await _session.directory.parent.create(recursive: true);
      staged = await _archiveService.stage(
        archiveBytes: bytes,
        stagingParent: _session.directory.parent,
      );
      final metadata = await _session.readStagedHeader(staged.directory);
      if (metadata == null) {
        throw const LifeVaultArchiveException('.lvault 缺少 Vault header');
      }
      if (staged.kind == 'attachments') {
        throw const LifeVaultArchiveException('请选择数据库或完整备份；原件包应在解锁后导入');
      }
      importedKey = await _session.authenticateStaged(
        staged.directory,
        backupPassword,
        metadata,
      );
      await _archiveService.verifyAuthentication(
        staged: staged,
        masterKey: importedKey,
      );
      if (metadata.formatVersion == 1) {
        await _session.disableStagedLegacyBiometric(staged.directory);
      }
      final harvested = await _harvestLocalOriginals(staged, epoch);
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
            if (await File('${staged.directory.path}/${entry.key}').exists()) {
              continue; // reused from the vault being replaced
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

      _checkEpoch(epoch);
      await _session.close();
      final installingEpoch = _session.operationEpoch;
      clearUnlockedData();
      transactionStarted = true;
      try {
        recoveryNotice = await _restoreTransaction.install(
          staged.directory,
          verifyInstalled: () async {
            _checkEpoch(installingEpoch);
            await _session.openWithKey(importedKey!);
            await _session.reloadHeader();
            _checkEpoch(installingEpoch);
            if (metadata.formatVersion == 1) {
              await VaultSnapshotQuery.inspectRepository(
                _session.repository,
                sessionGeneration: _session.sessionGeneration,
              );
            }
            _checkEpoch(installingEpoch);
          },
          closeInstalled: () async {
            await _session.close();
            clearUnlockedData();
          },
        );
        _checkEpoch(installingEpoch);
        // Credentials travel with the vault: a v3 header whose daily policy
        // this device can satisfy (the password branch always exists for
        // 'any') opens straight after install. Only 'all' policy vaults fall
        // back to the local security reset.
        final requiresReset =
            metadata.formatVersion == 3 && metadata.dailyPolicy != 'any';
        if (requiresReset) {
          _session.markRecovering();
        } else {
          _session.markUnlocked();
        }
        await _session.clearDeviceKeyAfterRestore();
        if (!requiresReset) {
          try {
            await refreshUnlockedData();
          } on Object {
            // The replacement is installed and open; a projection refresh
            // failure must never roll a valid vault back.
          }
        }
        return RestoreOutcome(
          harvestedOriginals: harvested,
          requiresReset: requiresReset,
          unlockedAfterRestore: !requiresReset,
        );
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
      try {
        if (!transactionStarted &&
            staged != null &&
            await staged.directory.exists()) {
          await staged.directory.delete(recursive: true);
        }
      } finally {
        if (importedKey != null) _wipe(importedKey);
      }
    }
  }

  /// Reuses originals already present in the vault being replaced: a blob
  /// whose ciphertext matches the incoming manifest descriptor byte for byte
  /// is copied into staging, so only genuinely missing originals are owed
  /// after the install. Pure file work; misses and IO errors simply leave the
  /// blob owed through `backup.missing`.
  Future<int> _harvestLocalOriginals(StagedLifeVault staged, int epoch) async {
    var harvested = 0;
    for (final entry in staged.omitted.entries) {
      _checkEpoch(epoch);
      final descriptor = entry.value;
      if (descriptor is! Map) continue;
      final source = File('${_session.directory.path}/${entry.key}');
      FileSystemEntityType type;
      try {
        type = await FileSystemEntity.type(source.path, followLinks: false);
      } on Object {
        continue;
      }
      if (type != FileSystemEntityType.file) continue;
      final target = File('${staged.directory.path}/${entry.key}');
      var keep = false;
      try {
        await target.parent.create(recursive: true);
        final hashSink = Sha256().newHashSink();
        var length = 0;
        final sink = target.openWrite();
        try {
          await for (final chunk in source.openRead()) {
            length += chunk.length;
            hashSink.add(chunk);
            sink.add(chunk);
          }
        } finally {
          await sink.close();
        }
        hashSink.close();
        final digest = await hashSink.hash();
        keep =
            length == descriptor['size'] &&
            base64UrlEncode(digest.bytes) == descriptor['sha256'];
      } on Object {
        keep = false;
      }
      if (keep) {
        harvested++;
      } else if (await target.exists()) {
        try {
          await target.delete();
        } on Object {
          // A partial staged copy is dropped with the staging directory on
          // failure; on success it is never referenced by the database.
        }
      }
    }
    return harvested;
  }

  Future<BackupPreview> inspect(Uint8List bytes, String password) =>
      _session.exclusiveMaintenance(() => _inspect(bytes, password));

  Future<BackupPreview> _inspect(Uint8List bytes, String password) async {
    final epoch = _session.operationEpoch;
    await _session.directory.parent.create(recursive: true);
    final staged = await _archiveService.stage(
      archiveBytes: bytes,
      stagingParent: _session.directory.parent,
    );
    Uint8List? key;
    VaultRepository? repository;
    try {
      final metadata = await _session.readStagedHeader(staged.directory);
      if (metadata == null) throw const LifeVaultArchiveException('备份缺少资料库头');
      if (staged.kind == 'attachments') {
        throw const LifeVaultArchiveException('原件补充包不能单独恢复资料库');
      }
      key = await _session.authenticateStaged(
        staged.directory,
        password,
        metadata,
      );
      await _archiveService.verifyAuthentication(
        staged: staged,
        masterKey: key,
      );
      final r = await _session.openTemporary(staged.directory, key);
      repository = r;
      final preview = BackupPreview(
        missingOriginals: staged.omitted.length,
        requiresReset:
            metadata.formatVersion == 3 && metadata.dailyPolicy != 'any',
        createdAt: staged.createdAt,
        cards: (await r.listCards()).length,
        credentials: (await r.listCredentials()).length,
        originals: (await r.listBlobs()).length,
        recycledCards: (await r.listCards(recycled: true)).length,
        recycledCredentials: (await r.listCredentials(recycled: true)).length,
      );
      _checkEpoch(epoch);
      return preview;
    } finally {
      try {
        await repository?.close();
      } finally {
        if (key != null) _wipe(key);
        if (await staged.directory.exists()) {
          await staged.directory.delete(recursive: true);
        }
      }
    }
  }

  Future<({Uint8List database, Uint8List attachments})> exportSplit(
    String credential,
    Future<void> Function() refresh,
  ) => _session.exclusiveMaintenance(() async {
    final identity = await _session.archiveIdentity();
    if (identity == null) {
      throw const LifeVaultArchiveException('分层备份需要先升级安全格式');
    }
    final snapshot = await stableArchiveSnapshotId(
      vaultId: identity.vaultId,
      epoch: identity.epoch,
    );
    return _exportAuthenticated(
      credential,
      refresh,
      (key) async {
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
        } on Object {
          _wipe(database);
          rethrow;
        }
      },
      (value) {
        _wipe(value.database);
        _wipe(value.attachments);
      },
    );
  });

  Future<int> missingCount() async {
    if (!_session.isUnlocked) return 0;
    final value = await _session.repository.readLocalValue('backup.missing');
    return value == null ? 0 : (jsonDecode(value) as Map).length;
  }

  Future<void> importSupplement(Uint8List bytes) => _consumeInput(
    bytes,
    () => _session.exclusiveMaintenance(() => _importSupplement(bytes)),
  );

  Future<void> _importSupplement(Uint8List bytes) async {
    if (!_session.isUnlocked) throw StateError('请先解锁');
    final epoch = _session.operationEpoch;
    final value = await _session.repository.readLocalValue('backup.missing');
    _checkEpoch(epoch);
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
          // Same key lineage (the usual device-to-device case): copy the
          // verified ciphertext byte for byte, keeping descriptors stable so
          // the next round trip can skip it again. After a rotation the keys
          // differ and blobs are re-encrypted under the current VMK instead.
          final sameKey = const ListEquality<int>().equals(oldKey, currentKey);
          for (final entry in missing.entries.toList()) {
            _checkEpoch(epoch);
            final descriptor = entry.value as Map;
            final file = File('${staged.directory.path}/${entry.key}');
            if (!await file.exists()) throw StateError('原件包缺少预期文件');
            final cipher = await file.readAsBytes();
            if (cipher.length != descriptor['size'] ||
                base64UrlEncode((await Sha256().hash(cipher)).bytes) !=
                    descriptor['sha256']) {
              _wipe(cipher);
              throw StateError('原件与数据库备份不匹配');
            }
            final blob = metadata.singleWhere(
              (b) => b.relativePath == entry.key,
            );
            if (sameKey) {
              await _session.writeBlobCiphertext(
                target: _session.directory,
                blob: blob,
                bytes: cipher,
              );
              _wipe(cipher);
            } else {
              _wipe(cipher);
              await _session.copyBlobUnderKey(
                source: staged.directory,
                target: _session.directory,
                oldKey: oldKey,
                newKey: currentKey,
                blob: blob,
              );
            }
            _checkEpoch(epoch);
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
    }
  }

  Future<T> _consumeInput<T>(
    Uint8List bytes,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } finally {
      _wipe(bytes);
    }
  }

  void _checkEpoch(int epoch) {
    if (epoch != _session.operationEpoch) throw StateError('资料库操作已取消');
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}
