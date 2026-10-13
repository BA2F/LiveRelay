import 'dart:io';
import 'dart:typed_data';

/// An encrypted, controlled staging directory. The adapter verifies paths and
/// descriptors before returning it; authentication must precede any install.
class StagedLifeVault {
  const StagedLifeVault({
    required this.directory,
    required this.manifestBytes,
    required this.manifestMac,
    this.version = 1,
    this.kind = 'full',
    this.snapshotId,
    this.omitted = const {},
    this.createdAt,
  });

  final DateTime? createdAt;
  final Directory directory;
  final Uint8List manifestBytes;
  final Uint8List manifestMac;
  final int version;
  final String kind;
  final String? snapshotId;
  final Map<String, Object?> omitted;
}

/// Plaintext summary of an archive's container header, used only to group
/// candidate packages on a transfer medium. It performs no cryptographic
/// verification; `stage` plus `verifyAuthentication` remain the real check.
class ArchiveContainerSummary {
  const ArchiveContainerSummary({
    required this.formatVersion,
    required this.kind,
    this.snapshotId,
    this.vaultId,
    this.createdAt,
  });

  final int formatVersion;
  final String kind;
  final String? snapshotId;
  final String? vaultId;
  final DateTime? createdAt;
}

abstract interface class VaultArchive {
  /// [blobPaths] restricts an `attachments` export to the given blob relative
  /// paths (as they appear in the vault directory); null means every blob.
  /// The parameter is ignored for `full` and `database` exports.
  Future<Uint8List> create({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    DateTime? createdAt,
    String kind = 'full',
    String? snapshotId,
    Set<String>? blobPaths,
  });
  Future<StagedLifeVault> stage({
    required Uint8List archiveBytes,
    required Directory stagingParent,
  });

  /// Reads the container header from a byte prefix of an archive without
  /// decoding the ZIP body. Returns null for anything that is not a readable
  /// container. This is package grouping metadata only; callers must still
  /// stage and authenticate before trusting any content.
  ArchiveContainerSummary? inspectContainerPrefix(Uint8List prefix);
  Future<void> verifyAuthentication({
    required StagedLifeVault staged,
    required Uint8List masterKey,
  });
}
