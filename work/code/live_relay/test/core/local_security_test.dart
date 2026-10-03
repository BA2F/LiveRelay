import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/identity/hpke.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_header_v3.dart';

import '../support/fictional_device_protection.dart';

Uint8List hex(String value) => Uint8List.fromList([
  for (var i = 0; i < value.length; i += 2)
    int.parse(value.substring(i, i + 2), radix: 16),
]);
void main() {
  test(
    'HPKE matches public CFRG RFC9180 AES256 Base vector, rejects altered AAD',
    () async {
      final vector = jsonDecode(
        await File('test/fixtures/local_completion/hpke-base-aes256.json')
            .readAsString(),
      ) as Map;
      final message = (vector['encryptions'] as List).first as Map;
      final box = await LocalHpke.seal(
        hex(message['pt']),
        hex(vector['pkRm']),
        hex(message['aad']),
        info: utf8.decode(hex(vector['info'])),
        ephemeralSeed: hex(vector['skEm']),
      );
      expect(HeaderEncoding.decodeBinary(box['enc'], 32), hex(vector['enc']));
      final ct = [
        ...base64Url.decode(base64Url.normalize(box['cipherText'] as String)),
        ...HeaderEncoding.decodeBinary(box['mac'], 16),
      ];
      expect(ct, hex(message['ct']));
      final pair = await X25519().newKeyPairFromSeed(hex(vector['skRm']));
      try {
        expect(
          await LocalHpke.open(
            box,
            pair,
            hex(message['aad']),
            info: utf8.decode(hex(vector['info'])),
          ),
          hex(message['pt']),
        );
        await expectLater(
          LocalHpke.open(box, pair, [
            1,
          ], info: utf8.decode(hex(vector['info']))),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      } finally {
        pair.destroy();
      }
    },
  );
  test('v3 OR allows password, file, device or independent recovery; any branch tamper fails', () async {
    final recovery = RecoveryCredential.generate(),
        device = FictionalDeviceProtection();
    final vmk = Uint8List.fromList(List.generate(32, (i) => i)),
        file = Uint8List.fromList(List.filled(32, 77));
    try {
      final h = await VaultHeaderV3.create(
        password: 'fictional-password',
        masterKey: vmk,
        recovery: recovery,
        keyFile: file,
        device: device,
      );
      expect(await h.unlock(password: 'fictional-password'), vmk);
      expect(await h.unlock(keyFile: file, preferred: 'keyFile'), vmk);
      expect(await h.unlock(device: device, preferred: 'device'), vmk);
      expect(await h.unlock(recovery: recovery), vmk);
      final modified = jsonDecode(utf8.decode(h.bytes)) as Map<String, Object?>;
      final slot =
          ((modified['branches'] as List).first as Map)['keySlot'] as Map;
      slot['mac'] = HeaderEncoding.binary(
        HeaderEncoding.decodeBinary(slot['mac'], 16)..[0] ^= 1,
      );
      final tampered = VaultHeaderV3.decode(HeaderEncoding.encode(modified));
      await expectLater(
        tampered.unlock(recovery: recovery),
        throwsFormatException,
      );
      await expectLater(
        h.unlock(keyFile: Uint8List(32), preferred: 'keyFile'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    } finally {
      recovery.dispose();
    }
  });
  test('v3 AND needs all factors before biometric prompt; recovery independently bypasses', () async {
    final r = RecoveryCredential.generate(),
        d = FictionalDeviceProtection(),
        key = Uint8List.fromList(List.filled(32, 12)),
        file = Uint8List.fromList(List.filled(32, 31));
    try {
      final h = await VaultHeaderV3.create(
        password: 'fictional-password',
        masterKey: key,
        recovery: r,
        keyFile: file,
        device: d,
        policy: 'all',
      );
      await expectLater(
        h.unlock(password: 'fictional-password', device: d),
        throwsFormatException,
      );
      expect(d.reads, 0);
      expect(
        await h.unlock(
          password: 'fictional-password',
          keyFile: file,
          device: d,
        ),
        key,
      );
      expect(d.reads, 1);
      expect(await h.unlock(recovery: r), key);
      expect(d.reads, 1);
      final invalid = jsonDecode(utf8.decode(h.bytes)) as Map<String, Object?>;
      invalid['dailyPolicy'] = 'any';
      expect(
        () => VaultHeaderV3.decode(HeaderEncoding.encode(invalid)),
        throwsFormatException,
      );
    } finally {
      r.dispose();
    }
  });
}
