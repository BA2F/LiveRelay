import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'header_encoding.dart';

class OwnerCrypto {
  static final cipher = AesGcm.with256bits();
  static Uint8List random(int n) =>
      Uint8List.fromList(List.generate(n, (_) => Random.secure().nextInt(256)));
  static Future<SecretKey> hkdf(
    List<int> secret,
    List<int> salt,
    String info,
  ) async {
    final input = SecretKey(secret);
    try {
      return await Hkdf(
        hmac: Hmac.sha256(),
        outputLength: 32,
      ).deriveKey(secretKey: input, nonce: salt, info: utf8.encode(info));
    } finally {
      input.destroy();
    }
  }

  static Future<SecretKey> password(String password, List<int> salt) async {
    final bytes = utf8.encode(password);
    if (bytes.isEmpty || bytes.length > 4096) {
      throw const FormatException('凭证输入长度错误');
    }
    final input = SecretKey(bytes);
    try {
      return await Argon2id(
        memory: 65536,
        iterations: 3,
        parallelism: 1,
        hashLength: 32,
      ).deriveKey(secretKey: input, nonce: salt);
    } finally {
      input.destroy();
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  static Future<Map<String, Object?>> seal(
    List<int> clear,
    SecretKey key,
    List<int> aad,
  ) async {
    final box = await cipher.encrypt(
      clear,
      secretKey: key,
      nonce: random(12),
      aad: aad,
    );
    return {
      'nonce': HeaderEncoding.binary(box.nonce),
      'cipherText': HeaderEncoding.binary(box.cipherText),
      'mac': HeaderEncoding.binary(box.mac.bytes),
    };
  }

  static Future<Uint8List> open(
    Map slot,
    SecretKey key,
    List<int> aad, {
    int length = 32,
  }) async => Uint8List.fromList(
    await cipher.decrypt(
      SecretBox(
        HeaderEncoding.decodeBinary(slot['cipherText'], length),
        nonce: HeaderEncoding.decodeBinary(slot['nonce'], 12),
        mac: Mac(HeaderEncoding.decodeBinary(slot['mac'], 16)),
      ),
      secretKey: key,
      aad: aad,
    ),
  );
  static Map<String, Object?> map(Object? value, Set<String> fields) {
    if (value is! Map<String, Object?> ||
        value.length != fields.length ||
        !fields.containsAll(value.keys)) {
      throw const FormatException('安全数据结构错误');
    }
    return value;
  }

  static void wipe(Uint8List? bytes) {
    if (bytes != null) bytes.fillRange(0, bytes.length, 0);
  }
}
