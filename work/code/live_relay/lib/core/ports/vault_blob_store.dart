import 'dart:io';
import 'dart:typed_data';

import '../domain/entities.dart';

/// Internal encrypted-file boundary. Only application services supply the VMK.
abstract interface class VaultBlobStore {
  Future<void> copyUnderKey({
    required Directory source,
    required Directory target,
    required Uint8List oldKey,
    required Uint8List newKey,
    required VaultBlob blob,
  });
  Future<VaultBlob> write({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required Uint8List clearBytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  });

  /// Writes already-authenticated ciphertext under the blob's relative path.
  /// Only valid when the bytes were encrypted with the vault's current VMK
  /// (the AAD binds the blob id, which the path already carries) and the
  /// caller verified them against the recorded descriptor. Writes through a
  /// temporary file so a partial copy can never look installed.
  Future<void> writeCiphertext({
    required Directory target,
    required VaultBlob blob,
    required Uint8List bytes,
  });

  Future<Uint8List> read({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required VaultBlob blob,
  });

  Future<void> delete({
    required Directory vaultDirectory,
    required VaultBlob blob,
  });
}
