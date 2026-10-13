import '../../core/domain/entities.dart';
import '../../core/ports/transfer_medium.dart';
import 'transfer_models.dart';

/// Decides which originals still need a volume on the medium.
///
/// Coverage is only trusted when the recorded index belongs to the current
/// snapshot AND the recorded volume is actually on the medium with the exact
/// length it was written with; anything else is re-exported. Within one
/// snapshot a blob's ciphertext never changes, so a covered path needs no
/// re-hash; the descriptor sizes ride along as a cheap file-size sanity check.
TransferPlan planTransfer({
  required String vaultTag,
  required String snapshot,
  required List<VaultBlob> blobs,
  required TransferIndex? index,
  required List<MediumEntry> mediumEntries,
  required int payloadLimit,
}) {
  final warnings = <String>[];
  TransferIndex? usable = index;
  if (index != null && index.snapshot != snapshot) {
    warnings.add('介质索引属于上一次换钥前的快照，原件将重新完整导出。');
    usable = null;
  }

  final byName = <String, MediumEntry>{
    for (final entry in mediumEntries) entry.name: entry,
  };
  final reusable = <TransferVolume>[];
  final coverage = <String, int>{};
  if (usable != null) {
    for (final volume in usable.volumes) {
      if (byName[volume.name]?.length != volume.bytes) {
        warnings.add('介质上的卷 ${volume.name} 缺失或长度不符，其原件将重新导出。');
        continue;
      }
      reusable.add(volume);
      coverage.addAll(volume.blobSizes);
    }
  }

  var skipped = 0;
  final pending = <VaultBlob>[];
  for (final blob in blobs) {
    if (coverage[blob.relativePath] ==
        blob.byteLength + blobCiphertextOverhead) {
      skipped++;
      continue;
    }
    pending.add(blob);
  }

  var nextNumber = 1;
  void observe(String name) {
    final match = transferVolumeNamePattern.firstMatch(name);
    if (match != null && match.group(1) == vaultTag) {
      final number = int.parse(match.group(2)!);
      if (number >= nextNumber) nextNumber = number + 1;
    }
  }

  for (final volume in reusable) {
    observe(volume.name);
  }
  for (final entry in mediumEntries) {
    observe(entry.name);
  }

  final volumes = <TransferVolumePlan>[];
  var current = <VaultBlob>[];
  var currentBytes = 0;
  void flush() {
    if (current.isEmpty) return;
    volumes.add(
      TransferVolumePlan(
        name: transferVolumeName(vaultTag, nextNumber++),
        blobSizes: {
          for (final blob in current)
            blob.relativePath: blob.byteLength + blobCiphertextOverhead,
        },
        estimatedBytes: currentBytes,
      ),
    );
    current = <VaultBlob>[];
    currentBytes = 0;
  }

  for (final blob in pending) {
    final size = blob.byteLength + blobCiphertextOverhead;
    if (size > payloadLimit) {
      // A single oversized original rides alone in its own volume.
      flush();
      current.add(blob);
      currentBytes = size;
      flush();
      continue;
    }
    if (current.isNotEmpty && currentBytes + size > payloadLimit) flush();
    current.add(blob);
    currentBytes += size;
  }
  flush();

  return TransferPlan(
    volumes: volumes,
    reusable: reusable,
    skippedBlobs: skipped,
    warnings: warnings,
  );
}
