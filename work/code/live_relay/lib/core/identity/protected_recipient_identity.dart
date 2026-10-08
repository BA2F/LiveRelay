import 'dart:convert';
import 'dart:typed_data';

import '../security/header_encoding.dart';
import '../security/owner_crypto.dart';

class ProtectedRecipientIdentity {
  static Map<String, Object?> decode(List<int> bytes) {
    if (bytes.length > 65536) throw const FormatException('身份文件过大');
    final v = OwnerCrypto.map(jsonDecode(utf8.decode(bytes)), {
      'version',
      'suite',
      'salt',
      'length',
      'box',
    });
    if (v['version'] != 1 ||
        v['suite'] != 'lr-recipient-argon2id64-aes256-v1' ||
        v['length'] is! int ||
        (v['length'] as int) < 1 ||
        (v['length'] as int) > 600000) {
      throw const FormatException('身份文件格式错误');
    }
    HeaderEncoding.decodeBinary(v['salt'], 16);
    final box = OwnerCrypto.map(v['box'], {'nonce', 'cipherText', 'mac'});
    HeaderEncoding.decodeBinary(box['nonce'], 12);
    HeaderEncoding.decodeBinary(box['mac'], 16);
    HeaderEncoding.decodeBinary(box['cipherText'], v['length'] as int);
    return v;
  }

  static List<int> aad(Uint8List salt, int length) => HeaderEncoding.encode({
    'version': 1,
    'suite': 'lr-recipient-argon2id64-aes256-v1',
    'salt': HeaderEncoding.binary(salt),
    'length': length,
  });
}
