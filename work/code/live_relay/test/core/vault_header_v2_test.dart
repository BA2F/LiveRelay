import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:archive/archive.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_header_v2.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';

const fixturePath = 'test/fixtures/header_v2';
Map<String, dynamic> fixtureInfo() =>
    jsonDecode(File('$fixturePath/vectors.json').readAsStringSync())
        as Map<String, dynamic>;
Map<String, Object?> headerMap([String name = 'custom.json']) =>
    jsonDecode(File('$fixturePath/$name').readAsStringSync())
        as Map<String, Object?>;
List<Map<String, dynamic>> branches(Map<String, Object?> h) =>
    (h['branches']! as List).cast<Map<String, dynamic>>();
void flip(Map<String, dynamic> slot, String field) {
  final bytes = HeaderEncoding.decodeBinary(
    slot[field],
    field == 'nonce'
        ? 12
        : field == 'mac'
        ? 16
        : 32,
  );
  bytes[0] ^= 1;
  slot[field] = HeaderEncoding.binary(bytes);
}

void main() {
  final info = fixtureInfo();
  for (final fixture in info['fixtures'] as List) {
    test(
      'independent ${fixture['file']} vector: password and recovery authenticate same VMK',
      () async {
        final h = VaultHeaderV2.decode(
          await File('$fixturePath/${fixture['file']}').readAsBytes(),
        );
        expect(
          HeaderEncoding.hex(await h.descriptorHash),
          fixture['descriptorHash'],
        );
        expect(
          utf8.decode(
            VaultHeaderV2.aad('factor', await h.descriptorHash, 'password'),
          ),
          fixture['passwordFactorAad'],
        );
        final key = await h.unlockPassword(
          fixture['canonicalPassword'] as String,
        );
        final r = await RecoveryCredential.parse(
          info['recoveryCredential'] as String,
        );
        try {
          final recovered = await h.unlockRecovery(r);
          expect(recovered, HeaderEncoding.decodeBinary(info['masterKey'], 32));
          expect(key, recovered);
          if (h.passwordKind == 'diceware-cn-v1') {
            final codec = ChinesePassphraseCodec.parse(
              await File('assets/wordlists/new-default-pinyin.wordlist')
                  .readAsString(),
            );
            final words = (fixture['canonicalPassword'] as String).split(' ');
            final chinese = words
                .map((p) => codec.words.firstWhere((w) => w.pinyin == p).hanzi)
                .join();
            expect(
              codec.canonicalize(chinese, wordCount: 6),
              fixture['canonicalPassword'],
            );
          }
          recovered.fillRange(0, recovered.length, 0);
        } finally {
          key.fillRange(0, key.length, 0);
          r.dispose();
        }
      },
    );
  }

  test(
    'wrong password/recovery and wrong known VMK fail without returning a key',
    () async {
      final h = VaultHeaderV2.decode(HeaderEncoding.encode(headerMap()));
      await expectLater(h.unlockPassword('x' * 4097), throwsFormatException);
      await expectLater(
        h.unlockPassword('fictional-wrong-password'),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final r = RecoveryCredential.generate();
      try {
        await expectLater(
          h.unlockRecovery(r),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
        await expectLater(
          h.verifyMasterKey(Uint8List(32)),
          throwsFormatException,
        );
      } finally {
        r.dispose();
      }
    },
  );

  final invalid = <String, void Function(Map<String, Object?>)>{
    'unknown version': (h) => h['formatVersion'] = 3,
    'float version': (h) => h['formatVersion'] = 2.0,
    'unknown suite': (h) => h['suite'] = 'unsupported',
    'AND policy': (h) => h['dailyPolicy'] = 'all',
    'old biometric VMK path': (h) => h['biometricEnabled'] = true,
    'unknown KDF': (h) => branches(h)[0]['kdfProfile'] = 'argon2id-m999999999',
    'arbitrary KDF resource field': (h) =>
        branches(h)[0]['memoryKiB'] = 999999999,
    'missing recovery': (h) => h['branches'] = [branches(h)[0]],
    'swapped branches': (h) => h['branches'] = branches(h).reversed.toList(),
    'duplicate branch': (h) => h['branches'] = [branches(h)[0], branches(h)[0]],
    'duplicate salt': (h) => branches(h)[1]['salt'] = branches(h)[0]['salt'],
    'duplicate nonce': (h) => (branches(h)[1]['factorSlot'] as Map)['nonce'] =
        (branches(h)[0]['factorSlot'] as Map)['nonce'],
    'padded encoding': (h) =>
        branches(h)[0]['salt'] = '${branches(h)[0]['salt']}==',
    'short nonce': (h) => (branches(h)[0]['factorSlot'] as Map)['nonce'] = 'AQ',
    'unknown top field': (h) => h['ignored'] = true,
    'invalid password mode': (h) => h['passwordKind'] = 'other',
    'wrong custom word count': (h) => h['wordCount'] = 6,
    'overflow epoch': (h) => h['headerEpoch'] = 2147483648,
  };
  for (final entry in invalid.entries) {
    test('rejects ${entry.key} before KDF', () {
      final h = headerMap();
      entry.value(h);
      expect(
        () => VaultHeaderV2.decode(HeaderEncoding.encode(h)),
        throwsFormatException,
      );
    });
  }

  test('rejects duplicate JSON keys, whitespace, escaped fields, floating numbers and size', () {
    final text = File('$fixturePath/custom.json').readAsStringSync();
    for (final invalid in [
      text.replaceFirst('{', '{"formatVersion":2,'),
      '$text\n',
      text.replaceFirst('"formatVersion"', '"format\\u0056ersion"'),
      text.replaceFirst('"headerEpoch":1', '"headerEpoch":1.0'),
    ]) {
      expect(
        () => VaultHeaderV2.decode(utf8.encode(invalid)),
        throwsFormatException,
      );
    }
    expect(
      () => VaultHeaderV2.decode(List.filled(65537, 32)),
      throwsFormatException,
    );
  });

  final tampering = <String, void Function(Map<String, Object?>)>{
    'vault ID': (h) => h['vaultId'] = '00' * 16,
    'epoch': (h) => h['headerEpoch'] = 2,
    'generation': (h) => h['keyGeneration'] = 2,
    'date': (h) => h['createdAt'] = '2026-10-04T00:00:00.000Z',
    'password factor slot': (h) => flip(
      branches(h)[0]['factorSlot'] as Map<String, dynamic>,
      'cipherText',
    ),
    'password key slot': (h) =>
        flip(branches(h)[0]['keySlot'] as Map<String, dynamic>, 'mac'),
    'recovery factor slot': (h) => flip(
      branches(h)[1]['factorSlot'] as Map<String, dynamic>,
      'cipherText',
    ),
    'recovery key nonce': (h) =>
        flip(branches(h)[1]['keySlot'] as Map<String, dynamic>, 'nonce'),
    'header MAC': (h) {
      final mac = HeaderEncoding.decodeBinary(h['headerMac'], 32)..[0] ^= 1;
      h['headerMac'] = HeaderEncoding.binary(mac);
    },
  };
  for (final entry in tampering.entries) {
    test(
      'recovery rejects tampered ${entry.key}, including unused password branch',
      () async {
        final h = headerMap();
        entry.value(h);
        final parsed = VaultHeaderV2.decode(HeaderEncoding.encode(h));
        final r = await RecoveryCredential.parse(
          info['recoveryCredential'] as String,
        );
        try {
          await expectLater(
            parsed.unlockRecovery(r),
            throwsA(isA<Exception>()),
          );
        } finally {
          r.dispose();
        }
      },
    );
  }

  test('cross-vault factor/key transplant is rejected', () async {
    final r = await RecoveryCredential.parse(
      info['recoveryCredential'] as String,
    );
    try {
      final other = await VaultHeaderV2.createForEvaluation(
        canonicalPassword: 'fictional-other-password',
        recovery: r,
        masterKey: Uint8List.fromList(List.filled(32, 7)),
      );
      final h = headerMap();
      final copy = jsonDecode(utf8.decode(other.bytes)) as Map<String, Object?>;
      branches(h)[1]['factorSlot'] = branches(copy)[1]['factorSlot'];
      branches(h)[1]['keySlot'] = branches(copy)[1]['keySlot'];
      await expectLater(
        VaultHeaderV2.decode(HeaderEncoding.encode(h)).unlockRecovery(r),
        throwsA(isA<Exception>()),
      );
    } finally {
      r.dispose();
    }
  });

  test('legacy independent fixture and default writer remain v1; v2 reader is explicit and device updates fail', () async {
    final root = await Directory.systemTemp.createTemp('header-compat-');
    addTearDown(() => root.delete(recursive: true));
    final file = File('${root.path}/vault-header.json');
    final manager = VaultKeyManager(root);
    await file.writeAsBytes(
      await File('$fixturePath/legacy.json').readAsBytes(),
    );
    final before = await file.readAsBytes();
    expect(
      await manager.unlock(info['legacyPassword'] as String),
      HeaderEncoding.decodeBinary(info['masterKey'], 32),
    );
    expect(await file.readAsBytes(), before);
    expect((await manager.readMetadata())!.formatVersion, 1);
    await expectLater(
      manager.unlockWithRecovery(info['recoveryCredential'] as String),
      throwsA(isA<VaultUnlockException>()),
    );
    await file.writeAsBytes(
      await File('$fixturePath/custom.json').readAsBytes(),
    );
    expect((await manager.readMetadata())!.recoveryEnabled, isTrue);
    expect(
      await manager.unlockWithRecovery(info['recoveryCredential'] as String),
      HeaderEncoding.decodeBinary(info['masterKey'], 32),
    );
    await expectLater(
      manager.setBiometricEnabled(true),
      throwsA(isA<VaultUnlockException>()),
    );
    final created = Directory('${root.path}/new-v1');
    await VaultKeyManager(created).create(
      canonicalPassword: 'fictional-default-password',
      passwordKind: 'custom',
    );
    expect((await VaultKeyManager(created).readMetadata())!.formatVersion, 1);
  });

  test(
    'legacy KDF resource inflation is rejected and v2 cannot be exported as v1',
    () async {
      final root = await Directory.systemTemp.createTemp('header-profile-');
      addTearDown(() => root.delete(recursive: true));
      final file = File('${root.path}/vault-header.json');
      final legacy = headerMap('legacy.json');
      (legacy['kdf'] as Map)['memoryKiB'] = 999999999;
      await file.writeAsBytes(HeaderEncoding.encode(legacy));
      await expectLater(
        VaultKeyManager(root).unlock(info['legacyPassword'] as String),
        throwsA(isA<VaultUnlockException>()),
      );
      await file.writeAsBytes(
        await File('$fixturePath/custom.json').readAsBytes(),
      );
      await File('${root.path}/vault.sqlite').writeAsBytes([1]);
      await expectLater(
        LifeVaultArchiveService().create(
          vaultDirectory: root,
          masterKey: HeaderEncoding.decodeBinary(info['masterKey'], 32),
        ),
        throwsA(isA<LifeVaultArchiveException>()),
      );
    },
  );

  test('LRR1 generation and checksum, strict spelling, disposal, and live-operation cancellation', () async {
    final r = await RecoveryCredential.parse(
      info['recoveryCredential'] as String,
    );
    expect(await r.encode(), info['recoveryCredential']);
    final generated = RecoveryCredential.generate();
    final text = await generated.encode();
    expect(text, hasLength(55));
    expect(text, isNot(info['recoveryCredential']));
    final copy = await RecoveryCredential.parse(' $text ');
    expect(await copy.encode(), text);
    for (final bad in [
      text.replaceFirst('LRR1', 'LRR2'),
      '$text=',
      '${text.substring(0, 54)}!',
      text.replaceRange(5, 6, text[5] == 'A' ? 'B' : 'A'),
    ]) {
      await expectLater(RecoveryCredential.parse(bad), throwsFormatException);
    }
    final pending = r.encode();
    r.dispose();
    await expectLater(pending, throwsStateError);
    await expectLater(r.encode(), throwsStateError);
    generated.dispose();
    copy.dispose();
  });

  test('RFC 5869 HKDF SHA256 case 1', () async {
    final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 42).deriveKey(
      secretKey: SecretKey(List.filled(22, 0x0b)),
      nonce: List.generate(13, (i) => i),
      info: List.generate(10, (i) => 0xf0 + i),
    );
    expect(
      HeaderEncoding.hex(await key.extractBytes()),
      '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865',
    );
    key.destroy();
  });
  test('RFC 9106 Argon2id v19 test vector', () async {
    final key =
        await Argon2id(
          memory: 32,
          iterations: 3,
          parallelism: 4,
          hashLength: 32,
        ).deriveKey(
          secretKey: SecretKey(List.filled(32, 1)),
          nonce: List.filled(16, 2),
          optionalSecret: List.filled(8, 3),
          associatedData: List.filled(12, 4),
        );
    expect(
      HeaderEncoding.hex(await key.extractBytes()),
      '0d640df58d78766c08c037a34a8b53c9d01ef0452d75b65eb52520e96b01e659',
    );
    key.destroy();
  });

  test('interrupted v2 header write recovers bounded candidate then authenticates it', () async {
    final root = await Directory.systemTemp.createTemp(
      'v2-header-interrupted-',
    );
    addTearDown(() => root.delete(recursive: true));
    final fixture = await File('$fixturePath/custom.json').readAsBytes();
    await File('${root.path}/vault-header.json.previous.tmp')
        .writeAsBytes(fixture);
    final manager = VaultKeyManager(root);
    expect((await manager.readMetadata())!.formatVersion, 2);
    expect(
      await manager.unlockWithRecovery(info['recoveryCredential'] as String),
      HeaderEncoding.decodeBinary(info['masterKey'], 32),
    );
    expect(await File('${root.path}/vault-header.json').readAsBytes(), fixture);
  });
  test(
    'v1 outer container refuses a disguised v2 header before staging',
    () async {
      final root = await Directory.systemTemp.createTemp('disguised-header-');
      addTearDown(() => root.delete(recursive: true));
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'container.json',
            jsonEncode({
              'format': LifeVaultArchiveService.formatName,
              'formatVersion': 1,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({'formatVersion': 1, 'entries': {}}),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'manifest.mac',
            base64UrlEncode(List.filled(32, 0)),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'vault/vault-header.json',
            File('$fixturePath/custom.json').readAsStringSync(),
          ),
        );
      await expectLater(
        LifeVaultArchiveService().stage(
          archiveBytes: ZipEncoder().encodeBytes(archive),
          stagingParent: root,
        ),
        throwsA(
          isA<LifeVaultArchiveException>().having(
            (e) => e.message,
            'format mismatch',
            contains('v1 不支持'),
          ),
        ),
      );
      expect(await root.list().isEmpty, isTrue);
    },
  );
  test(
    'legacy unknown wrapping algorithms and malformed slots are rejected',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'legacy-slot-validation-',
      );
      addTearDown(() => root.delete(recursive: true));
      for (final field in ['algorithm', 'nonce', 'mac', 'cipherText']) {
        final legacy = headerMap('legacy.json');
        (legacy['passwordSlot'] as Map)[field] = field == 'algorithm'
            ? 'other-cipher'
            : 'AQ==';
        await File('${root.path}/vault-header.json')
            .writeAsBytes(HeaderEncoding.encode(legacy));
        await expectLater(
          VaultKeyManager(root).unlock(info['legacyPassword'] as String),
          throwsA(isA<VaultUnlockException>()),
        );
      }
    },
  );
}
