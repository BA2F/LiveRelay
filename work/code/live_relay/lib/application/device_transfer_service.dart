import 'dart:io';

import '../core/domain/entities.dart';
import '../core/ports/transfer_medium.dart';
import '../core/ports/vault_archive.dart';
import 'transfer/transfer_models.dart';
import 'vault_backup_service.dart';

/// Orchestrates C-mode device transfer（「整库搬运」）on top of the backup
/// service: scanning a medium, restoring a database package (which reuses
/// matching local originals) and consuming the original volumes that pair
/// with it. All cryptography stays in [VaultBackupService]; this layer only
/// sequences it and reports honestly.
class DeviceTransferService {
  DeviceTransferService({
    required this._backup,
    required this._archive,
  });

  final VaultBackupService _backup;
  final VaultArchive _archive;

  /// Volume payload budget. `create` builds archives in memory, so the cap is
  /// also the memory ceiling; phones get half the desktop budget.
  static int get defaultPayloadLimit =>
      Platform.isAndroid || Platform.isIOS
      ? 64 * 1024 * 1024
      : 128 * 1024 * 1024;

  /// Groups the packages on a medium by their plaintext container headers.
  /// Package names on the medium are produced by this app, but the scan never
  /// trusts them: every `*.lvault` candidate is sniffed by prefix, and real
  /// authentication still happens during restore or supplement import.
  Future<TransferMediumScan> scan(TransferMedium medium) async {
    final databases = <MediumPackage>[];
    final volumes = <MediumPackage>[];
    final unmatched = <MediumPackage>[];
    final warnings = <String>[];
    for (final entry in await medium.list()) {
      if (!entry.name.endsWith('.lvault')) continue;
      final prefix = await medium.readPrefix(entry.name, 64 * 1024);
      final summary = _archive.inspectContainerPrefix(prefix);
      if (summary == null) {
        unmatched.add(
          MediumPackage(name: entry.name, length: entry.length, kind: 'unknown'),
        );
        continue;
      }
      final package = MediumPackage(
        name: entry.name,
        length: entry.length,
        kind: summary.kind,
        snapshotId: summary.snapshotId,
        vaultId: summary.vaultId,
        createdAt: summary.createdAt,
      );
      switch (summary.kind) {
        case 'database':
          databases.add(package);
        case 'attachments':
          volumes.add(package);
        default:
          unmatched.add(package);
      }
    }
    if (databases.length > 1) {
      warnings.add('介质上有多个数据库包，导入前请确认选择哪一个。');
    }
    return TransferMediumScan(
      databases: databases,
      volumes: volumes,
      unmatched: unmatched,
      warnings: warnings,
    );
  }

  /// Authenticates and describes one database package without touching the
  /// live vault. The bytes are wiped here; `inspect` does not consume them.
  Future<BackupPreview> inspectMedium(
    TransferMedium medium,
    String databaseName,
    String credential,
  ) async {
    final bytes = await medium.read(databaseName);
    try {
      return await _backup.inspect(bytes, credential);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  /// Imports a database package (whole-vault replacement, no merge), reuses
  /// matching local originals, then consumes the volumes that pair with the
  /// package. With a pre-export credential the current vault is exported to
  /// the medium first, so the replaced state stays recoverable.
  Future<TransferImportReport> importFromMedium(
    TransferMedium medium, {
    required String databaseName,
    required String credential,
    String? preExportCredential,
    required void Function() clearUnlockedData,
    required Future<void> Function() refreshUnlockedData,
  }) async {
    TransferExportOutcome? preExport;
    if (preExportCredential != null) {
      preExport = await _backup.exportTransferToMedium(
        medium,
        preExportCredential,
        refreshUnlockedData: refreshUnlockedData,
        payloadLimit: defaultPayloadLimit,
      );
    }
    final mediumScan = await scan(medium);
    MediumPackage? database;
    for (final candidate in mediumScan.databases) {
      if (candidate.name == databaseName) database = candidate;
    }
    if (database == null) throw StateError('介质上没有找到该数据库包');
    final bytes = await medium.read(database.name);
    final RestoreOutcome restored;
    try {
      restored = await _backup.restore(
        bytes,
        credential,
        clearUnlockedData: clearUnlockedData,
        refreshUnlockedData: refreshUnlockedData,
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    final matching = mediumScan.volumesMatching(database.snapshotId);
    if (!restored.unlockedAfterRestore) {
      // 'all' policy vaults wait for the local security reset before any
      // supplement can be decrypted under the recorded key.
      return TransferImportReport(
        databaseName: database.name,
        requiresReset: true,
        harvestedOriginals: restored.harvestedOriginals,
        volumesConsumed: 0,
        pendingVolumes: [for (final volume in matching) volume.name],
        volumeErrors: const [],
        remainingMissingOriginals: -1,
        preExport: preExport,
      );
    }
    final consumed = await _consumeVolumes(medium, matching);
    final remaining = await _backup.missingCount();
    return TransferImportReport(
      databaseName: database.name,
      requiresReset: false,
      harvestedOriginals: restored.harvestedOriginals,
      volumesConsumed: consumed.consumed.length,
      pendingVolumes: remaining > 0
          ? [
              for (final volume in matching)
                if (!consumed.consumed.contains(volume.name)) volume.name,
            ]
          : const [],
      volumeErrors: consumed.errors,
      remainingMissingOriginals: remaining,
      preExport: preExport,
    );
  }

  /// Retries the volumes for the owed-originals ledger of the current vault;
  /// used after a required security reset finishes, or after a partial import.
  Future<TransferImportReport> importPendingVolumes(TransferMedium medium) async {
    final snapshot = await _backup.pendingSnapshot();
    if (snapshot == null) throw StateError('当前没有待补齐的原件');
    final mediumScan = await scan(medium);
    final matching = mediumScan.volumesMatching(snapshot);
    final consumed = await _consumeVolumes(medium, matching);
    final remaining = await _backup.missingCount();
    return TransferImportReport(
      requiresReset: false,
      harvestedOriginals: 0,
      volumesConsumed: consumed.consumed.length,
      pendingVolumes: remaining > 0
          ? [
              for (final volume in matching)
                if (!consumed.consumed.contains(volume.name)) volume.name,
            ]
          : const [],
      volumeErrors: consumed.errors,
      remainingMissingOriginals: remaining,
    );
  }

  Future<({Set<String> consumed, List<String> errors})> _consumeVolumes(
    TransferMedium medium,
    List<MediumPackage> volumes,
  ) async {
    final consumed = <String>{};
    final errors = <String>[];
    for (final volume in volumes) {
      if (await _backup.missingCount() == 0) break;
      final bytes = await medium.read(volume.name);
      try {
        await _backup.importSupplement(bytes);
        consumed.add(volume.name);
      } on Object catch (error) {
        errors.add('${volume.name}：$error');
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    }
    return (consumed: consumed, errors: errors);
  }
}
