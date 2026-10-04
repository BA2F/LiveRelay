import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:live_relay/core/ports/device_factor_protection.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/security/android_device_factor_protection.dart';

import '../test/support/verification_fakes.dart';

// Host backgrounds only the isolated .verification activity at the READY marker.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical creation and onStop cancel cannot unlock the database',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final root = await (await getApplicationSupportDirectory()).createTemp(
        'device-cancel-',
      );
      final native = AndroidDeviceFactorProtection();
      final c = createAppController(
        root,
        null,
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
        null,
        native,
      );
      final manager = VaultKeyManager(
        Directory('${root.path}/live_relay/vault'),
      );
      Future<void> stage(String text) async {
        debugPrint('DEVICE_CANCEL: $text');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(child: Text(text, textAlign: TextAlign.center)),
            ),
          ),
        );
        await tester.pump();
      }

      try {
        await c.initialize();
        final r = await c.generateRecovery();
        await stage('请触摸一次指纹：新建带指纹的虚构资料库');
        await c.setupModernVault(
          password: 'fictional-cancel-password',
          recoveryText: r,
          recoveryConfirmation: r,
          biometric: true,
        );
        expect(c.isUnlocked, isTrue);
        await c.lock();
        await stage('请勿触摸指纹：自动检查后台取消');
        final cancelled = expectLater(
          c.unlockWithBiometric(),
          throwsA(
            isA<DeviceFactorException>().having(
              (e) => e.failure,
              'failure',
              DeviceFactorFailure.cancelled,
            ),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 700));
        debugPrint('HOST_BACKGROUND_READY');
        await cancelled.timeout(const Duration(seconds: 20));
        expect(c.isUnlocked, isFalse);
        expect(c.lastError, contains('取消'));
        await c.unlockDaily(password: 'fictional-cancel-password');
        expect(c.isUnlocked, isTrue);
        await stage('新建指纹库、后台取消与密码恢复通过');
      } finally {
        await c.lock();
        final header = await manager.readV3();
        for (final reference in header?.deviceReferences ?? <String>[]) {
          await native.deleteFactor(reference);
        }
        c.dispose();
        await tester.pumpWidget(const SizedBox());
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
