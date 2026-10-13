import 'dart:convert';

/// Ciphertext overhead of one encrypted blob file: 8-byte magic, 12-byte
/// nonce, 16-byte GCM tag. Kept here for size planning only; the blob store
/// remains the format owner.
const int blobCiphertextOverhead = 36;

String transferDatabaseName(String vaultTag) =>
    'LiveRelay-$vaultTag-database.lvault';

String transferVolumeName(String vaultTag, int index) =>
    'LiveRelay-$vaultTag-originals-${index.toString().padLeft(4, '0')}.lvault';

final RegExp transferVolumeNamePattern = RegExp(
  r'^LiveRelay-([0-9a-f]{8})-originals-(\d{4,})\.lvault$',
);

/// A package found on the medium, described by its plaintext container header.
/// Grouping metadata only — authentication still happens in `stage`.
class MediumPackage {
  const MediumPackage({
    required this.name,
    required this.length,
    required this.kind,
    this.snapshotId,
    this.vaultId,
    this.createdAt,
  });

  final String name;
  final int length;
  final String kind;
  final String? snapshotId;
  final String? vaultId;
  final DateTime? createdAt;
}

class TransferMediumScan {
  const TransferMediumScan({
    this.databases = const [],
    this.volumes = const [],
    this.unmatched = const [],
    this.warnings = const [],
  });

  final List<MediumPackage> databases;
  final List<MediumPackage> volumes;
  final List<MediumPackage> unmatched;
  final List<String> warnings;

  List<MediumPackage> volumesMatching(String? snapshot) => snapshot == null
      ? const []
      : [
          for (final volume in volumes)
            if (volume.snapshotId == snapshot) volume,
        ];
}

/// One entry in the export index: a volume file and the blobs it carries.
/// Sizes are ciphertext lengths; content verification lives in the volume's
/// VMK-authenticated manifest, not here.
class TransferVolume {
  const TransferVolume({
    required this.name,
    required this.bytes,
    required this.blobSizes,
  });

  final String name;
  final int bytes;
  final Map<String, int> blobSizes;

  Map<String, Object> encode() => <String, Object>{
    'name': name,
    'bytes': bytes,
    'blobs': blobSizes,
  };

  static TransferVolume? decode(Object? raw) {
    if (raw is! Map) return null;
    final name = raw['name'], bytes = raw['bytes'], blobs = raw['blobs'];
    if (name is! String || bytes is! int || blobs is! Map) return null;
    final sizes = <String, int>{};
    for (final entry in blobs.entries) {
      final key = entry.key, value = entry.value;
      if (key is! String || value is! int) return null;
      sizes[key] = value;
    }
    return TransferVolume(name: name, bytes: bytes, blobSizes: sizes);
  }
}

/// What this vault has already written to a medium (key `transfer.volumes`).
/// It rides inside the encrypted database, so the vault that receives the
/// next package inherits the coverage and only exports the delta.
class TransferIndex {
  const TransferIndex({required this.snapshot, required this.volumes});

  static const version = 1;
  final String snapshot;
  final List<TransferVolume> volumes;

  String encode() => jsonEncode(<String, Object>{
    'version': version,
    'snapshot': snapshot,
    'volumes': [for (final volume in volumes) volume.encode()],
  });

  /// Null when the stored value is absent, has another version, or is
  /// unreadable; callers then treat the medium as having no reusable coverage.
  static TransferIndex? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map || decoded['version'] != version) return null;
      final snapshot = decoded['snapshot'];
      final volumes = decoded['volumes'];
      if (snapshot is! String || volumes is! List) return null;
      final parsed = <TransferVolume>[];
      for (final raw in volumes) {
        final volume = TransferVolume.decode(raw);
        if (volume == null) return null;
        parsed.add(volume);
      }
      return TransferIndex(snapshot: snapshot, volumes: parsed);
    } on Object {
      return null;
    }
  }
}

class TransferVolumePlan {
  const TransferVolumePlan({
    required this.name,
    required this.blobSizes,
    required this.estimatedBytes,
  });

  final String name;
  final Map<String, int> blobSizes;
  final int estimatedBytes;

  List<String> get blobPaths => blobSizes.keys.toList(growable: false);
}

class TransferPlan {
  const TransferPlan({
    required this.volumes,
    required this.reusable,
    required this.skippedBlobs,
    required this.warnings,
  });

  final List<TransferVolumePlan> volumes;
  final List<TransferVolume> reusable;
  final int skippedBlobs;
  final List<String> warnings;
}

class TransferExportOutcome {
  const TransferExportOutcome({
    required this.databaseName,
    required this.writtenVolumes,
    required this.skippedBlobs,
    required this.indexPersisted,
    required this.warnings,
  });

  final String databaseName;
  final List<TransferVolume> writtenVolumes;
  final int skippedBlobs;
  final bool indexPersisted;
  final List<String> warnings;
}

class TransferImportReport {
  const TransferImportReport({
    this.databaseName,
    required this.requiresReset,
    required this.harvestedOriginals,
    required this.volumesConsumed,
    required this.pendingVolumes,
    required this.volumeErrors,
    required this.remainingMissingOriginals,
    this.preExport,
  });

  /// Null when this report only covers a later volume top-up.
  final String? databaseName;
  final bool requiresReset;
  final int harvestedOriginals;
  /// Volumes verified and consumed this round. A consumed volume may still
  /// have carried nothing this device owed (its blobs can live in a sibling
  /// volume); the owed count below is the number that matters.
  final int volumesConsumed;

  /// Volume names that could still hold owed originals (a reset is pending,
  /// or some volumes failed this round).
  final List<String> pendingVolumes;
  final List<String> volumeErrors;

  /// Owed originals after this round; -1 while the vault waits for the local
  /// security reset and cannot count them.
  final int remainingMissingOriginals;
  final TransferExportOutcome? preExport;
}
