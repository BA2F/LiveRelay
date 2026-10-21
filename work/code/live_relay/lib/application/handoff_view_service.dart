import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/security/header_encoding.dart';
import '../core/security/owner_crypto.dart';
import '../core/storage/file_commit.dart';

/// A long-term, password-protected read-only handoff.
///
/// The same envelope is used for the local view kept beside the vault and for
/// the package a recipient downloads from the cloud. [encode] and [openBytes]
/// work without a file so the cloud path can upload the bytes directly.
class HandoffViewService {
  HandoffViewService(this._resolveFile);

  final Future<File> Function() _resolveFile;
  static const kind = 'handoff-view';
  static const _maximumClearBytes = 128 * 1024 * 1024;

  Future<File> _file() => _resolveFile();

  Future<bool> exists() async => (await _file()).exists();

  /// Reads only the non-secret envelope fields.
  Future<DateTime?> updatedAt() async {
    final file = await _file();
    if (!await file.exists()) return null;
    final envelope = _readEnvelopeJson(await file.readAsString());
    return DateTime.tryParse(envelope['updatedAt'] as String);
  }

  Future<bool> accepts(String password) async {
    try {
      await open(password);
      return true;
    } on FormatException {
      return false;
    } on StateError {
      return false;
    }
  }

  /// Builds the encrypted envelope without touching a file.
  ///
  /// Callers wipe the returned bytes after upload. [snapshot] is not copied;
  /// the caller must not keep mutable views into it.
  Future<Uint8List> encode({
    required String password,
    required Map<String, Object?> snapshot,
  }) async {
    if (password.isEmpty) throw const FormatException('取件密码不能为空');
    final salt = OwnerCrypto.random(16);
    final key = await OwnerCrypto.password(password, salt);
    try {
      final updatedAt = DateTime.now().toUtc().toIso8601String();
      final header = <String, Object?>{
        'version': 1,
        'kind': kind,
        'salt': HeaderEncoding.binary(salt),
        'updatedAt': updatedAt,
      };
      final clear = utf8.encode(jsonEncode({...snapshot, 'date': updatedAt}));
      if (clear.length > _maximumClearBytes) {
        throw StateError('交接内容过大');
      }
      try {
        final box = await OwnerCrypto.seal(
          clear,
          key,
          HeaderEncoding.encode(header),
        );
        return Uint8List.fromList(
          utf8.encode(jsonEncode({...header, 'box': box})),
        );
      } finally {
        clear.fillRange(0, clear.length, 0);
      }
    } finally {
      key.destroy();
    }
  }

  Future<void> save({
    required String password,
    required Map<String, Object?> snapshot,
  }) async {
    final bytes = await encode(password: password, snapshot: snapshot);
    try {
      final file = await _file();
      await file.parent.create(recursive: true);
      final pending = File('${file.path}.tmp');
      await pending.writeAsBytes(bytes, flush: true);
      await commitFile(pending, file);
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Map<String, Object?>> open(String password) async {
    final file = await _file();
    if (!await file.exists()) throw StateError('本机还没有可查看的交接内容');
    return openBytes(await file.readAsBytes(), password);
  }

  /// Opens an envelope received as a file (the recipient flow).
  Future<Map<String, Object?>> openBytes(
    Uint8List bytes,
    String password,
  ) async {
    final envelope = _readEnvelopeJson(
      utf8.decode(bytes, allowMalformed: false),
    );
    final salt = HeaderEncoding.decodeBinary(envelope['salt'], 16);
    final box = OwnerCrypto.map(envelope['box'], {
      'nonce',
      'cipherText',
      'mac',
    });
    final cipherLength = _binary(box['cipherText']).length;
    final key = await OwnerCrypto.password(password, salt);
    try {
      final clear = await OwnerCrypto.open(
        box,
        key,
        HeaderEncoding.encode({
          'version': envelope['version'],
          'kind': envelope['kind'],
          'salt': envelope['salt'],
          'updatedAt': envelope['updatedAt'],
        }),
        length: cipherLength,
      );
      try {
        final decoded = jsonDecode(utf8.decode(clear));
        if (decoded is! Map<String, Object?>) {
          throw const FormatException('交接内容格式错误');
        }
        return decoded;
      } finally {
        OwnerCrypto.wipe(clear);
      }
    } on SecretBoxAuthenticationError {
      throw const FormatException('取件码或交接密码不正确');
    } finally {
      key.destroy();
    }
  }

  Map<String, Object?> _readEnvelopeJson(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> ||
        decoded['version'] != 1 ||
        decoded['kind'] != kind ||
        decoded['salt'] is! String ||
        decoded['updatedAt'] is! String ||
        decoded['box'] is! Map) {
      throw const FormatException('交接内容文件格式错误');
    }
    return decoded;
  }

  static Uint8List _binary(Object? text) {
    if (text is! String || !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(text)) {
      throw const FormatException('交接内容编码错误');
    }
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(text)));
  }
}
