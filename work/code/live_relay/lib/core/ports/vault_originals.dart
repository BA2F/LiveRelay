import 'dart:typed_data';

import '../domain/entities.dart';
import 'unlocked_vault.dart';

/// Authenticated original storage operations. The session owns encryption keys;
/// use cases receive bytes only for the operation they requested.
abstract interface class VaultOriginals implements UnlockedVault {
  Future<VaultBlob> writeOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  });
  Future<Uint8List> readOriginal(VaultBlob blob);
  Future<void> deleteOriginal(VaultBlob blob);
}
