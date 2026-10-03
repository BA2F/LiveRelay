import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../security/header_encoding.dart';
import '../security/owner_crypto.dart';

/// RFC 9180 Base, DHKEM(X25519, HKDF-SHA256), HKDF-SHA256, AES-256-GCM.
/// One message per fresh encapsulation, sequence zero. No reusable context API.
class LocalHpke {
  static final _kem = [...ascii.encode('KEM'), 0, 32];
  static final _suite = [...ascii.encode('HPKE'), 0, 32, 0, 1, 0, 2];
  static final _dh = X25519();
  static Future<Uint8List> _extract(
    List<int> salt,
    List<int> suite,
    String label,
    List<int> input,
  ) async {
    final key = SecretKey(salt.isEmpty ? List.filled(32, 0) : salt);
    try {
      return Uint8List.fromList(
        (await Hmac.sha256().calculateMac([
          ...ascii.encode('HPKE-v1'),
          ...suite,
          ...ascii.encode(label),
          ...input,
        ], secretKey: key)).bytes,
      );
    } finally {
      key.destroy();
    }
  }

  static Future<Uint8List> _expand(
    List<int> prk,
    List<int> suite,
    String label,
    List<int> info,
    int length,
  ) async {
    assert(length <= 32);
    final key = SecretKey(prk);
    try {
      return Uint8List.fromList(
        (await Hmac.sha256().calculateMac([
          0,
          length,
          ...ascii.encode('HPKE-v1'),
          ...suite,
          ...ascii.encode(label),
          ...info,
          1,
        ], secretKey: key)).bytes.take(length).toList(),
      );
    } finally {
      key.destroy();
    }
  }

  static Future<({Uint8List key, Uint8List nonce})> _schedule(
    SimpleKeyPair pair,
    SimplePublicKey public,
    List<int> enc,
    List<int> recipient,
    List<int> info,
  ) async {
    final secret = await _dh.sharedSecretKey(
      keyPair: pair,
      remotePublicKey: public,
    );
    final dh = Uint8List.fromList(await secret.extractBytes());
    secret.destroy();
    if (dh.every((b) => b == 0)) throw const FormatException('无效接收者公钥');
    Uint8List? prk, shared, secretPrk, pskHash, infoHash;
    try {
      prk = await _extract([], _kem, 'eae_prk', dh);
      shared = await _expand(prk, _kem, 'shared_secret', [
        ...enc,
        ...recipient,
      ], 32);
      pskHash = await _extract([], _suite, 'psk_id_hash', []);
      infoHash = await _extract([], _suite, 'info_hash', info);
      secretPrk = await _extract(shared, _suite, 'secret', []);
      final context = [0, ...pskHash, ...infoHash];
      return (
        key: await _expand(secretPrk, _suite, 'key', context, 32),
        nonce: await _expand(secretPrk, _suite, 'base_nonce', context, 12),
      );
    } finally {
      for (final value in [dh, prk, shared, secretPrk, pskHash, infoHash]) {
        OwnerCrypto.wipe(value);
      }
    }
  }

  static Future<Map<String, Object?>> seal(
    List<int> clear,
    List<int> recipient,
    List<int> aad, {
    String info = 'LiveRelay/ScopedDelivery/v1',
    Uint8List? ephemeralSeed,
  }) async {
    if (recipient.length != 32) throw const FormatException('接收者密钥错误');
    final pair = ephemeralSeed == null
        ? await _dh.newKeyPair()
        : await _dh.newKeyPairFromSeed(ephemeralSeed);
    final enc = (await pair.extractPublicKey()).bytes;
    final schedule = await _schedule(
      pair,
      SimplePublicKey(recipient, type: KeyPairType.x25519),
      enc,
      recipient,
      utf8.encode(info),
    );
    final key = SecretKey(schedule.key);
    try {
      final box = await AesGcm.with256bits().encrypt(
        clear,
        secretKey: key,
        nonce: schedule.nonce,
        aad: aad,
      );
      return {
        'enc': HeaderEncoding.binary(enc),
        'cipherText': HeaderEncoding.binary(box.cipherText),
        'mac': HeaderEncoding.binary(box.mac.bytes),
      };
    } finally {
      key.destroy();
      pair.destroy();
      OwnerCrypto.wipe(schedule.key);
      OwnerCrypto.wipe(schedule.nonce);
    }
  }

  static Future<Uint8List> open(
    Map<String, Object?> box,
    SimpleKeyPair pair,
    List<int> aad, {
    String info = 'LiveRelay/ScopedDelivery/v1',
  }) async {
    OwnerCrypto.map(box, {'enc', 'cipherText', 'mac'});
    final enc = HeaderEncoding.decodeBinary(box['enc'], 32);
    final text = box['cipherText'];
    if (text is! String || text.length > 180 * 1024 * 1024) {
      throw const FormatException('交接包大小错误');
    }
    final cipher = base64Url.decode(base64Url.normalize(text));
    if (HeaderEncoding.binary(cipher) != text) {
      throw const FormatException('交接编码错误');
    }
    final recipient = (await pair.extractPublicKey()).bytes;
    final schedule = await _schedule(
      pair,
      SimplePublicKey(enc, type: KeyPairType.x25519),
      enc,
      recipient,
      utf8.encode(info),
    );
    final key = SecretKey(schedule.key);
    try {
      return Uint8List.fromList(
        await AesGcm.with256bits().decrypt(
          SecretBox(
            cipher,
            nonce: schedule.nonce,
            mac: Mac(HeaderEncoding.decodeBinary(box['mac'], 16)),
          ),
          secretKey: key,
          aad: aad,
        ),
      );
    } finally {
      key.destroy();
      OwnerCrypto.wipe(schedule.key);
      OwnerCrypto.wipe(schedule.nonce);
    }
  }
}
