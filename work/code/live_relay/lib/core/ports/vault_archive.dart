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

abstract interface class VaultArchive {
  Future<Uint8List> create({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    DateTime? createdAt,
    String kind = 'full',
    String? snapshotId,
  });
  Future<StagedLifeVault> stage({
    required Uint8List archiveBytes,
    required Directory stagingParent,
  });
  Future<void> verifyAuthentication({
    required StagedLifeVault staged,
    required Uint8List masterKey,
  });
}
