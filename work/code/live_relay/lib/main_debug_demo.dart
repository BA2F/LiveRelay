import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'application/local_handoff_service.dart';
import 'core/identity/local_identity.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'application/app_preferences.dart';
import 'application/app_controller.dart';
import 'core/domain/entities.dart';
import 'core/ports/biometric_key_store.dart';
import 'core/ports/device_factor_protection.dart';
import 'core/ports/development_controls.dart';
import 'infrastructure/app_composition.dart';
import 'presentation/app.dart';
import 'development/demo_controls.dart';

/// Explicit demo entry point. Every runtime service receives this fresh root.
/// Never reads or upgrades a production vault and never exports demo as real.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final root = await Directory.systemTemp.createTemp('liverelay-demo-');
  final controls = DemoControls(root);
  final controller = createAppController(
    root,
    _NoBiometrics(),
    null,
    null,
    null,
    null,
    _NoDevice(),
    () => controls.now,
  );
  controls.controller = controller;
  await controller.initialize();
  final r = await controller.generateRecovery();
  await controller.setupModernVault(
    password: 'Demo-only-2026',
    recoveryText: r,
    recoveryConfirmation: r,
  );
  await controller.createCard(
    const CardDraft(
      title: '演示：家庭资料位置',
      content: '这是虚构资料：保单副本在蓝色文件夹里。',
      kind: CardKind.location,
    ),
  );
  await controller.createCard(
    const CardDraft(
      title: '演示：想交代的事',
      content: '这是虚构留言，用来演示不同可见级别。',
      kind: CardKind.wish,
    ),
  );
  await controller.saveCredential(
    const CredentialDraft(
      title: '演示账户（无效）',
      username: 'demo@example.invalid',
      secret: 'fictional-only-password',
      website: 'https://example.invalid',
    ),
  );
  await controller.handoff!.saveProfile(
    '演示所有者',
    'demo@example.invalid',
    '完全虚构，本次演示数据位于独立临时目录',
  );
  await controller.recipient!.initialize();
  await controller.recipient!.create('演示接收者', 'Recipient-demo-2026');
  final receiver = controller.recipient!;
  final public = await receiver.identity!.publicData();
  final fingerprint = await receiver.identity!.fingerprint();
  final challenge = jsonDecode(
    utf8.decode(await controller.handoff!.createChallenge(public, fingerprint)),
  ) as Map<String, Object?>;
  final ownerFingerprint = await LocalIdentity.fingerprintOf(
    await controller.handoff!.publicIdentity(),
  );
  final proof = jsonDecode(
    utf8.decode(await receiver.answerChallenge(challenge, ownerFingerprint)),
  ) as Map<String, Object?>;
  await controller.handoff!.acceptProof(proof);
  final package = await controller.handoff!.exportScope(fingerprint, [
    ScopedRecord('card', controller.cards.first.id, VisibilityLevel.summary),
  ]);
  try {
    await receiver.receive(package, ownerFingerprint);
  } finally {
    package.fillRange(0, package.length, 0);
  }
  receiver.lock();
  final preferences = createAppPreferences(
    File('${root.path}/demo-preferences.json'),
  );
  await preferences.finishOnboarding();
  debugPrint('独立演示已初始化：${root.path}');
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppController>.value(value: controller),
        ChangeNotifierProvider<AppPreferences>.value(value: preferences),
        Provider<DevelopmentControls>.value(value: _DemoEntry(controls)),
      ],
      child: LiveRelayApp(
        environmentOverlay: controls.buildOverlay,
        navigatorKey: controls.navigatorKey,
      ),
    ),
  );
}

class _NoBiometrics implements BiometricKeyStore {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> saveMasterKey(Uint8List key) async =>
      throw UnsupportedError('Demo');
  @override
  Future<Uint8List?> readMasterKey() async => null;
  @override
  Future<void> clear() async {}
}

class _NoDevice implements DeviceFactorProtection {
  @override
  Future<DeviceFactorCapability> capability() async =>
      const DeviceFactorCapability(
        available: false,
        reason: 'Demo has no device key',
      );
  @override
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  ) async => throw UnsupportedError('Demo');
  @override
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor wrapped,
  ) async => throw UnsupportedError('Demo');
  @override
  Future<void> deleteFactor(String reference) async {}
  @override
  Future<void> cancel() async {}
}

class _DemoEntry implements DevelopmentControls {
  const _DemoEntry(this.controls);
  final DemoControls controls;
  @override
  void activate() => controls.activate();
}
