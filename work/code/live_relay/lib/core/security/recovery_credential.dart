import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'header_encoding.dart';

/// Independent 256-bit recovery secret. The encoded value grants full access.
/// No secret bytes are exposed to rendering or provider APIs.
class RecoveryCredential {
  RecoveryCredential._(this._secret);
  final Uint8List _secret;
  bool _disposed = false;
  static const _domain = 'LiveRelay/RecoveryCredential/LRR1';

  static RecoveryCredential generate() {
    final random = Random.secure();
    return RecoveryCredential._(
      Uint8List.fromList(List.generate(32, (_) => random.nextInt(256))),
    );
  }

  static Future<RecoveryCredential> parse(String text) async {
    final value = text.trim();
    if (value.length != 55 || !value.startsWith('LRR1-') || value[48] != '-') {
      throw const FormatException('恢复凭证格式或校验不正确');
    }
    Uint8List? secret;
    try {
      secret = HeaderEncoding.decodeBinary(value.substring(5, 48), 32);
      final checksum = HeaderEncoding.decodeBinary(value.substring(49), 4);
      final expected = await _checksum(secret);
      if (Mac(checksum) != Mac(expected)) throw const FormatException();
      final result = RecoveryCredential._(secret);
      secret = null;
      return result;
    } on Object {
      throw const FormatException('恢复凭证格式或校验不正确');
    } finally {
      secret?.fillRange(0, secret.length, 0);
    }
  }

  static Future<List<int>> _checksum(List<int> secret) async =>
      (await Sha256().hash([...utf8.encode(_domain), ...secret])).bytes
          .sublist(0, 4);

  Future<String> encode() async {
    _requireLive();
    final copy = Uint8List.fromList(_secret);
    try {
      final checksum = await _checksum(copy);
      _requireLive();
      return 'LRR1-${HeaderEncoding.binary(copy)}-${HeaderEncoding.binary(checksum)}';
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  Future<SecretKey> deriveWrappingKey(
    List<int> salt, {
    String domain = 'LiveRelay/Header/v2/RecoveryFactor',
  }) async {
    _requireLive();
    final input = SecretKey(_secret);
    try {
      final key = await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(secretKey: input, nonce: salt, info: utf8.encode(domain));
      if (_disposed) {
        key.destroy();
        throw StateError('恢复凭证已释放');
      }
      return key;
    } finally {
      input.destroy();
    }
  }

  void _requireLive() {
    if (_disposed) throw StateError('恢复凭证已释放');
  }

  void dispose() {
    _disposed = true;
    _secret.fillRange(0, _secret.length, 0);
  }
}
