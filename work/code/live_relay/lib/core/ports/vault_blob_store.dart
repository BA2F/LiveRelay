import 'dart:io';
import 'dart:typed_data';

import '../domain/entities.dart';

/// Internal encrypted-file boundary. Only application services supply the VMK.
abstract interface class VaultBlobStore {
  Future<VaultBlob> write({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required Uint8List clearBytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
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
