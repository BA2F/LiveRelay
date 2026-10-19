import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/security/header_encoding.dart';
import '../core/security/owner_crypto.dart';
import '../core/storage/file_commit.dart';

/// A long-term, password-protected read-only handoff kept beside the vault.
///
/// The recipient reads it on the same machine from the unlock screen. The
/// password is shared with the recipient and replaces the recipient identity
/// key as the gate: whoever knows the password can open the snapshot.
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
    final envelope = await _readEnvelope(file);
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

  Future<void> save({
    required String password,
    required Map<String, Object?> snapshot,
  }) async {
    if (password.isEmpty) throw const FormatException('交接密码不能为空');
    final file = await _file();
    await file.parent.create(recursive: true);
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
        final pending = File('${file.path}.tmp');
        await pending.writeAsString(
          jsonEncode({...header, 'box': box}),
          flush: true,
        );
        await commitFile(pending, file);
      } finally {
        clear.fillRange(0, clear.length, 0);
      }
    } finally {
      key.destroy();
    }
  }

  Future<Map<String, Object?>> open(String password) async {
    final file = await _file();
    if (!await file.exists()) throw StateError('本机还没有可查看的交接内容');
    final envelope = await _readEnvelope(file);
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
      throw const FormatException('交接密码不正确');
    } finally {
      key.destroy();
    }
  }

  Future<Map<String, Object?>> _readEnvelope(File file) async {
    final decoded = jsonDecode(await file.readAsString());
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
