import 'package:live_relay/infrastructure/backup/vault_restore_transaction.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/core/ports/device_factor_protection.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_header_v2.dart';

import '../support/fictional_device_protection.dart';
import '../support/session_fakes.dart';
import '../support/verification_fakes.dart';

class RejectLegacyStore extends NoBiometrics {
  @override
  Future<bool> isAvailable() async =>
      throw StateError('legacy capability read');
  @override
  Future<Uint8List?> readMasterKey() async =>
      throw StateError('legacy key read');
}

void main() {
  const password = 'fictional-device-password';
  final vmk = Uint8List.fromList(List.generate(32, (i) => i));
  late RecoveryCredential recovery;
  late FictionalDeviceProtection protection;
  late VaultHeaderV2 header;
  setUp(() async {
    recovery = RecoveryCredential.generate();
    protection = FictionalDeviceProtection();
    header = await VaultHeaderV2.createForEvaluation(
      canonicalPassword: password,
      recovery: recovery,
      masterKey: vmk,
      deviceProtection: protection,
    );
  });
  tearDown(() async {
    recovery.dispose();
    await protection.deleteFactor(header.deviceReference!);
  });

  test(
    'password, recovery and device independently authenticate the same vault',
    () async {
      expect(header.biometricEnabled, true);
      expect(await header.unlockPassword(password), vmk);
      expect(await header.unlockRecovery(recovery), vmk);
      expect(await header.unlockDevice(protection), vmk);
      expect(protection.borrowedShare, everyElement(0));
      protection.failure = DeviceFactorFailure.invalidated;
      await expectLater(
        header.unlockDevice(protection),
        throwsA(isA<DeviceFactorException>()),
      );
      expect(await header.unlockPassword(password), vmk);
      expect(await header.unlockRecovery(recovery), vmk);
    },
  );

  test(
    'changing device reference or unused password ciphertext is rejected',
    () async {
      final changed =
          jsonDecode(utf8.decode(header.bytes)) as Map<String, Object?>;
      final branches = changed['branches']! as List;
      (branches[2] as Map)['deviceReference'] = '0' * 32;
      final transplanted = VaultHeaderV2.decode(HeaderEncoding.encode(changed));
      await expectLater(
        transplanted.unlockRecovery(recovery),
        throwsA(isA<Exception>()),
      );
      final fresh =
          jsonDecode(utf8.decode(header.bytes)) as Map<String, Object?>;
      final slot = ((fresh['branches']! as List)[0] as Map)['keySlot'] as Map;
      final bytes = HeaderEncoding.decodeBinary(slot['cipherText'], 32)
        ..[0] ^= 1;
      slot['cipherText'] = HeaderEncoding.binary(bytes);
      await expectLater(
        VaultHeaderV2.decode(HeaderEncoding.encode(fresh))
            .unlockDevice(protection),
        throwsA(isA<Exception>()),
      );
    },
  );

  test('device suite cannot be hidden in old suite or use another profile', () {
    final changed =
        jsonDecode(utf8.decode(header.bytes)) as Map<String, Object?>;
    changed['suite'] = VaultHeaderV2.suite;
    expect(
      () => VaultHeaderV2.decode(HeaderEncoding.encode(changed)),
      throwsFormatException,
    );
    changed['suite'] = VaultHeaderV2.deviceSuite;
    ((changed['branches']! as List)[2] as Map)['deviceProfile'] = 'pin';
    expect(
      () => VaultHeaderV2.decode(HeaderEncoding.encode(changed)),
      throwsFormatException,
    );
  });

  test('cancelled creation never returns a header or deletes an unacknowledged device reference', () async {
    final cancelled = FictionalDeviceProtection()
      ..failure = DeviceFactorFailure.cancelled;
    await expectLater(
      VaultHeaderV2.createForEvaluation(
        canonicalPassword: password,
        recovery: recovery,
        masterKey: vmk,
        deviceProtection: cancelled,
      ),
      throwsA(isA<DeviceFactorException>()),
    );
    expect(cancelled.deletes, 0);
    expect(cancelled.borrowedShare, everyElement(0));
  });

  test('session never opens database on cancelled device auth or late result after lock', () async {
    final dir = await Directory.systemTemp.createTemp(
      'fictional-device-session-',
    );
    var opens = 0;
    final session = VaultSession(
      installationFactory: (directory) => VaultRestoreTransaction(directory),
      resolveDirectory: () async => dir,
      loadPassphraseCodec: () async => ChinesePassphraseCodec.parse(
        await File('assets/wordlists/new-default-pinyin.wordlist')
            .readAsString(),
      ),
      openRepository: (_, key) async {
        opens++;
        expect(key, vmk);
        return SessionRepository();
      },
      biometricKeyStore: RejectLegacyStore(),
      blobStore: TrackingBlobStore(),
      deviceFactorProtection: protection,
    );
    try {
      await File('${dir.path}/vault-header.json').writeAsBytes(header.bytes);
      await File('${dir.path}/vault.sqlite').writeAsBytes([1]);
      await session.prepare();
      await session.inspect();
      protection.failure = DeviceFactorFailure.cancelled;
      await expectLater(
        session.unlockWithBiometric(),
        throwsA(isA<DeviceFactorException>()),
      );
      expect(opens, 0);
      expect(session.state, VaultSessionState.locked);
      protection.failure = null;
      final hold = Completer<void>();
      protection.holdRead = hold.future;
      final late = session.unlockWithBiometric();
      final rejected = expectLater(late, throwsA(isA<DeviceFactorException>()));
      while (protection.reads < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      await session.close();
      hold.complete();
      await rejected;
      expect(opens, 0);
      protection.holdRead = null;
      await session.unlockWithBiometric();
      expect(opens, 1);
      await session.close();
      await session.unlockWithPassword(password);
      expect(opens, 2);
    } finally {
      await session.close();
      await dir.delete(recursive: true);
    }
  });
}
