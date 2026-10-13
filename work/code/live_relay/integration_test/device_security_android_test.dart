import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:live_relay/core/ports/device_factor_protection.dart';
import 'package:live_relay/infrastructure/security/android_device_factor_protection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../test/support/verification_fakes.dart';

// Physical authorization is performed by the person at the device. All vaults
// are fictional, inside the separate .verification Android app sandbox.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical Android fingerprint rekey, unlock and limited recovery',
    (tester) async {
      expect(Platform.isAndroid, isTrue);
      final support = await getApplicationSupportDirectory();
      final root = await support.createTemp('physical-security-');
      final physical = AuditedPhysicalDevice();
      final c = createAppController(
        root,
        null,
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
        null,
        physical,
      );
      Future<void> stage(String text) async {
        debugPrint('DEVICE_SECURITY: $text');
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
        await stage('初始化隔离测试库');
        await c.initialize();
        expect(
          c.biometricAvailable,
          isTrue,
          reason: 'Requires an enrolled physical strong biometric',
        );
        final r1 = await c.generateRecovery();
        await stage('创建密码库（无指纹基线）');
        await c.setupModernVault(
          password: 'fictional-before-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await c.createCard(const CardDraft(title: '虚构真机记录', content: 'before'));
        final cardId = c.cards.single.id;
        await c.updateCard(
          cardId,
          const CardDraft(title: '虚构真机记录', content: 'after'),
        );
        await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional-original')),
          originalName: 'fictional.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        final blobId = c.blobs.single.id;
        final r2 = await c.generateRecovery();
        await stage('请触摸指纹：启用指纹并换钥');
        await c.configureSecurity(
          oldPassword: 'fictional-before-password',
          newPassword: 'fictional-after-password',
          recoveryText: r2,
          recoveryConfirmation: r2,
          biometric: true,
        );
        expect(c.isUnlocked, isTrue);
        expect(c.header!.biometricEnabled, isTrue);
        await c.lock();
        await stage('换钥后用密码重新解锁');
        await c.unlockDaily(password: 'fictional-after-password');
        expect(utf8.decode(await c.readOriginal(blobId)), 'fictional-original');
        await c.lock();
        await stage('请触摸指纹：解锁隔离测试库');
        await c.unlockWithBiometric();
        expect(c.isUnlocked, isTrue);
        expect((await c.cardHistory(cardId)).map((r) => r.content), [
          'after',
          'before',
        ]);
        expect(utf8.decode(await c.readOriginal(blobId)), 'fictional-original');
        await stage('独立恢复与分层备份');
        final pair = await c.exportSplitVault(r2);
        // Rotate between export and restore so the local ciphertext no longer
        // matches the package descriptor; otherwise the restore reuses it.
        final r2b = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: 'fictional-after-password',
          newPassword: 'fictional-rotated-password',
          recoveryText: r2b,
          recoveryConfirmation: r2b,
        );
        await c.restoreVault(pair.database, r2);
        // Credentials travel with the vault: a satisfiable daily policy opens
        // straight after install.
        expect(c.sessionState.name, 'unlocked');
        expect(c.cards.map((v) => v.id), contains(cardId));
        expect(await c.missingOriginalCount(), 1);
        final r3 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: 'fictional-after-password',
          newPassword: 'fictional-recovered-password',
          recoveryText: r3,
          recoveryConfirmation: r3,
        );
        expect(await c.missingOriginalCount(), 1);
        await c.importOriginalSupplement(pair.attachments);
        expect(await c.missingOriginalCount(), 0);
        expect(utf8.decode(await c.readOriginal(blobId)), 'fictional-original');
        expect((await c.cardHistory(cardId)).map((r) => r.content), [
          'after',
          'before',
        ]);
        await c.lock();
        await expectLater(c.beginRecovery(r2), throwsA(anything));
        await c.beginRecovery(r3);
        expect(c.sessionState.name, 'recovering');
        expect(c.cards, isEmpty);
        await stage('真机指纹／换钥／分层恢复验证通过');
      } finally {
        await c.lock();
        c.dispose();
        physical.dispose();
        await tester.pumpWidget(const SizedBox());
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

// Audits the real MethodChannel roundtrip using only random fictional shares.
class AuditedPhysicalDevice implements DeviceFactorProtection {
  final native = AndroidDeviceFactorProtection();
  final expected = <String, Uint8List>{};
  @override
  Future<DeviceFactorCapability> capability() => native.capability();
  @override
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  ) async {
    expected[context.reference] = Uint8List.fromList(share);
    return native.protectFactor(context, share);
  }

  @override
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor box,
  ) async {
    final share = await native.unprotectFactor(context, box);
    final matches = listEquals(share, expected[context.reference]);
    debugPrint(
      'DEVICE_SECURITY: native roundtrip matches=$matches, zero=${share.every((v) => v == 0)}',
    );
    if (!matches) {
      share.fillRange(0, share.length, 0);
      throw StateError('Physical native share roundtrip failed');
    }
    return share;
  }

  @override
  Future<void> deleteFactor(String reference) async {
    final share = expected.remove(reference);
    share?.fillRange(0, share.length, 0);
    await native.deleteFactor(reference);
  }

  @override
  Future<void> cancel() => native.cancel();
  void dispose() {
    for (final share in expected.values) {
      share.fillRange(0, share.length, 0);
    }
    expected.clear();
  }
}
