import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/header_encoding.dart';
import '../security/owner_crypto.dart';

class LocalIdentity {
  LocalIdentity(this.name, this.dh, this.signing);
  final String name;
  final SimpleKeyPair dh, signing;
  static Future<LocalIdentity> create(String name) async {
    validateName(name);
    return LocalIdentity(
      name.trim(),
      await X25519().newKeyPair(),
      await Ed25519().newKeyPair(),
    );
  }

  static void validateName(String name) {
    if (name.trim().isEmpty || name.length > 100) {
      throw const FormatException('身份名称需为 1–100 个字符');
    }
  }

  Future<Map<String, Object?>> publicData() async => {
    'version': 1,
    'name': HeaderEncoding.binary(utf8.encode(name)),
    'encryptionKey': HeaderEncoding.binary((await dh.extractPublicKey()).bytes),
    'signingKey': HeaderEncoding.binary(
      (await signing.extractPublicKey()).bytes,
    ),
  };
  Future<String> fingerprint() async => fingerprintOf(await publicData());
  static Map<String, Object?> validatePublic(Object? value) {
    final p = OwnerCrypto.map(value, {
      'version',
      'name',
      'encryptionKey',
      'signingKey',
    });
    if (p['version'] != 1 ||
        p['name'] is! String ||
        (p['name'] as String).length > 600) {
      throw const FormatException('身份格式错误');
    }
    validateName(
      utf8.decode(base64Url.decode(base64Url.normalize(p['name'] as String))),
    );
    HeaderEncoding.decodeBinary(p['encryptionKey'], 32);
    HeaderEncoding.decodeBinary(p['signingKey'], 32);
    return p;
  }

  static String displayName(Map public) => utf8.decode(
    base64Url.decode(base64Url.normalize(public['name'] as String)),
  );
  static Future<String> fingerprintOf(Map<String, Object?> public) async {
    validatePublic(public);
    return HeaderEncoding.hex(
      (await Sha256().hash(
        HeaderEncoding.encode({
          'domain': 'LiveRelay/Identity/v1',
          'encryptionKey': public['encryptionKey'],
          'signingKey': public['signingKey'],
        }),
      )).bytes,
    );
  }

  Future<Map<String, Object?>> privateData() async => {
    'version': 1,
    'name': name,
    'dhSeed': HeaderEncoding.binary(await dh.extractPrivateKeyBytes()),
    'signSeed': HeaderEncoding.binary(await signing.extractPrivateKeyBytes()),
  };
  static Future<LocalIdentity> fromPrivate(Map value) async {
    final data = Map<String, Object?>.from(value);
    OwnerCrypto.map(data, {'version', 'name', 'dhSeed', 'signSeed'});
    if (data['version'] != 1 || data['name'] is! String) {
      throw const FormatException('身份密钥格式错误');
    }
    validateName(data['name'] as String);
    final d = HeaderEncoding.decodeBinary(data['dhSeed'], 32),
        s = HeaderEncoding.decodeBinary(data['signSeed'], 32);
    try {
      return LocalIdentity(
        data['name'] as String,
        await X25519().newKeyPairFromSeed(d),
        await Ed25519().newKeyPairFromSeed(s),
      );
    } finally {
      OwnerCrypto.wipe(d);
      OwnerCrypto.wipe(s);
    }
  }

  Future<String> sign(List<int> bytes) async => HeaderEncoding.binary(
    (await Ed25519().sign(bytes, keyPair: signing)).bytes,
  );
  static Future<void> verify(
    Map<String, Object?> public,
    List<int> bytes,
    Object? signature,
  ) async {
    validatePublic(public);
    if (!await Ed25519().verify(
      bytes,
      signature: Signature(
        HeaderEncoding.decodeBinary(signature, 64),
        publicKey: SimplePublicKey(
          HeaderEncoding.decodeBinary(public['signingKey'], 32),
          type: KeyPairType.ed25519,
        ),
      ),
    )) {
      throw const FormatException('交接签名验证失败');
    }
  }

  void dispose() {
    dh.destroy();
    signing.destroy();
  }

  static Uint8List encodeJson(Object data) =>
      Uint8List.fromList(utf8.encode(jsonEncode(data)));
}
