import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import '../../core/domain/entities.dart';
import '../../core/ports/vault_blob_store.dart';

class EncryptedBlobException implements Exception {
  const EncryptedBlobException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// AES-256-GCM encrypted original-file storage. Disk names are random IDs;
/// original names and hashes live only inside the SQLCipher database.
class EncryptedBlobStore implements VaultBlobStore {
  EncryptedBlobStore({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  static final _magic = Uint8List.fromList(utf8.encode('LRBLB001'));
  static const _aadPrefix = 'LiveRelay/EncryptedBlob/v1/';
  static const maximumInMemoryBytes = 256 * 1024 * 1024;

  final Uuid _uuid;
  final _cipher = AesGcm.with256bits();
  final _sha256 = Sha256();

  @override
  Future<VaultBlob> write({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required Uint8List clearBytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async {
    if (clearBytes.isEmpty) {
      throw const FormatException('不能导入空文件');
    }
    if (clearBytes.length > maximumInMemoryBytes) {
      throw const FormatException('MVP 单个原始资料不能超过 256 MB');
    }
    final id = _uuid.v7();
    final relativePath = 'blobs/$id.blob';
    final target = File(path.join(vaultDirectory.path, 'blobs', '$id.blob'));
    final temporary = File('${target.path}.tmp');
    await target.parent.create(recursive: true);
    try {
      final box = await _cipher.encrypt(
        clearBytes,
        secretKey: SecretKey(masterKey),
        aad: utf8.encode('$_aadPrefix$id'),
      );
      final output = BytesBuilder(copy: false)
        ..add(_magic)
        ..add(box.nonce)
        ..add(box.mac.bytes)
        ..add(box.cipherText);
      await temporary.writeAsBytes(output.takeBytes(), flush: true);
      await temporary.rename(target.path);
      final digest = await _sha256.hash(clearBytes);
      return VaultBlob(
        id: id,
        originalName: _safeDisplayName(originalName),
        mediaKind: mediaKind,
        mimeType: mimeType.trim().isEmpty
            ? 'application/octet-stream'
            : mimeType.trim(),
        relativePath: relativePath,
        byteLength: clearBytes.length,
        sha256: base64UrlEncode(digest.bytes),
        createdAt: DateTime.now().toUtc(),
      );
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      if (await target.exists()) await target.delete();
      rethrow;
    }
  }

  @override
  Future<Uint8List> read({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required VaultBlob blob,
  }) async {
    _validateRelativePath(blob.relativePath);
    final file = File(path.join(vaultDirectory.path, blob.relativePath));
    if (!await file.exists()) {
      throw const EncryptedBlobException('加密原始资料文件不存在');
    }
    final bytes = await file.readAsBytes();
    const headerLength = 8 + 12 + 16;
    if (bytes.length < headerLength || !_startsWith(bytes, _magic)) {
      throw const EncryptedBlobException('加密原始资料格式错误');
    }
    try {
      final box = SecretBox(
        bytes.sublist(headerLength),
        nonce: bytes.sublist(8, 20),
        mac: Mac(bytes.sublist(20, headerLength)),
      );
      final clear = await _cipher.decrypt(
        box,
        secretKey: SecretKey(masterKey),
        aad: utf8.encode('$_aadPrefix${blob.id}'),
      );
      final result = Uint8List.fromList(clear);
      final digest = await _sha256.hash(result);
      if (result.length != blob.byteLength ||
          base64UrlEncode(digest.bytes) != blob.sha256) {
        result.fillRange(0, result.length, 0);
        throw const EncryptedBlobException('原始资料完整性校验失败');
      }
      return result;
    } on SecretBoxAuthenticationError {
      throw const EncryptedBlobException('原始资料解密失败或已被篡改');
    }
  }

  @override
  Future<void> delete({
    required Directory vaultDirectory,
    required VaultBlob blob,
  }) async {
    _validateRelativePath(blob.relativePath);
    final file = File(path.join(vaultDirectory.path, blob.relativePath));
    if (await file.exists()) await file.delete();
  }

  String _safeDisplayName(String name) {
    final normalized = name.replaceAll('\\', '/').split('/').last.trim();
    return normalized.isEmpty ? '未命名原始资料' : normalized;
  }

  void _validateRelativePath(String value) {
    final segments = value.replaceAll('\\', '/').split('/');
    if (segments.length != 2 ||
        segments.first != 'blobs' ||
        segments.any(
          (segment) => segment.isEmpty || segment == '.' || segment == '..',
        )) {
      throw const EncryptedBlobException('非法原始资料路径');
    }
  }

  bool _startsWith(Uint8List bytes, Uint8List prefix) {
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }
}
