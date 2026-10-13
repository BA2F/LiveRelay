import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'header_encoding.dart';

/// Deterministic snapshot identity for layered archives.
///
/// A vault keeps the same snapshot across exports while its key generation
/// (epoch) is unchanged, so attachment volumes exported by either side stay
/// pairable; rotating credentials moves the snapshot forward and deliberately
/// orphans every earlier volume. The value is grouping metadata only, not a
/// secret: manifests stay authenticated by the VMK-derived MAC.
Future<String> stableArchiveSnapshotId({
  required String vaultId,
  required int epoch,
}) async {
  final digest = await Sha256().hash(
    utf8.encode('LiveRelay/LifeVaultSnapshot/v1/$vaultId/$epoch'),
  );
  return HeaderEncoding.hex(
    Uint8List.fromList(digest.bytes.sublist(0, 16)),
  );
}
