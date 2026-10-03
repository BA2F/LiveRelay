import 'package:flutter/material.dart' hide SnapshotController;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/app_preferences.dart';
import 'package:live_relay/application/device_capabilities.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/pages/home_shell.dart';
import 'package:live_relay/presentation/pages/onboarding_page.dart';
import 'package:live_relay/presentation/widgets/credential_secret_actions.dart';

import 'ux_widget_test.dart' show SnapshotController, app;

class SetupController extends SnapshotController {
  SetupController() {
    sessionState = VaultSessionState.needsSetup;
  }
  int creations = 0;
  @override
  Future<void> setupVault({
    required String password,
    required bool usesChinesePassphrase,
    int? wordCount,
    bool enableBiometric = false,
  }) async {
    creations++;
    sessionState = VaultSessionState.unlocked;
    notifyListeners();
  }
}

Widget configuredApp(AppController c, AppPreferences p, {double scale = 1}) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: c),
        ChangeNotifierProvider.value(value: p),
      ],
      child: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: const LiveRelayApp(),
      ),
    );

void main() {
  test(
    'password is an information card; summary and search never expose Secret',
    () {
      final c = SnapshotController();
      expect(c.credentials.single, isA<InformationCard>());
      final summaries = c.findInformationCards('');
      expect(summaries, hasLength(2));
      expect(
        summaries.singleWhere((s) => s.isPassword).preview,
        'test@example.com',
      );
      expect(c.findInformationCards('hidden-test-secret'), isEmpty);
      expect(c.findInformationCards('test@example'), hasLength(1));
      expect(
        c.findInformationCards('', passwordsOnly: true).single.recordId,
        'mail',
      );
      expect(
        c.findInformationCards('', status: CardStatus.draft).single.recordId,
        'one',
      );
      c.dispose();
    },
  );
  test('platform matrix keeps unavailable tools explicit', () {
    for (final platform in [DevicePlatform.linux, DevicePlatform.windows]) {
      final d = DeviceCapabilities(platform);
      expect(d.feature(AppFeature.camera).status, CapabilityStatus.unsupported);
      expect(d.feature(AppFeature.ocr).status, CapabilityStatus.unsupported);
      expect(d.feature(AppFeature.mediaPlayback).isAvailable, isFalse);
      expect(d.feature(AppFeature.biometric).isAvailable, isFalse);
    }
    const android = DeviceCapabilities(DevicePlatform.android);
    expect(android.feature(AppFeature.camera).isAvailable, isTrue);
    expect(
      android.feature(AppFeature.biometric).status,
      CapabilityStatus.needsSetup,
    );
    expect(
      android
          .feature(AppFeature.biometric, biometricAvailable: true)
          .isAvailable,
      isTrue,
    );
    expect(
      android.feature(AppFeature.agent).status,
      CapabilityStatus.needsSetup,
    );
  });
  testWidgets(
    'new user chooses appearance, creates vault once, and finishes only after success',
    (tester) async {
      final c = SetupController();
      final p = AppPreferences();
      await p.load(hasExistingVault: false);
      await tester.pumpWidget(configuredApp(c, p));
      expect(find.text('欢迎使用留灯'), findsOneWidget);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('深色'));
      await tester.pumpAndSettle();
      expect(p.appearance, AppearanceMode.dark);
      await tester.tap(find.text('继续'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建资料库'));
      await tester.pumpAndSettle();
      expect(p.onboardingStarted, isTrue);
      expect(p.onboardingComplete, isFalse);
      await tester.tap(find.text('自定密码'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField).at(0),
        'setup-test-password',
      );
      await tester.enterText(
        find.byType(TextField).at(1),
        'setup-test-password',
      );
      await tester.ensureVisible(find.text('我已妥善保存口令'));
      await tester.tap(find.text('我已妥善保存口令'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('创建并进入资料库'));
      await tester.tap(find.text('创建并进入资料库'));
      await tester.pumpAndSettle();
      expect(c.creations, 1);
      expect(find.text('准备好了'), findsOneWidget);
      expect(p.onboardingComplete, isFalse);
      await tester.tap(find.text('开始使用'));
      await tester.pumpAndSettle();
      expect(p.onboardingComplete, isTrue);
      expect(find.text('我的'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
    },
  );
  testWidgets(
    'unfinished setup resumes after unlock; legacy vault skips setup',
    (tester) async {
      final c = SnapshotController()..sessionState = VaultSessionState.unlocked;
      final p = AppPreferences();
      await p.load(hasExistingVault: true);
      await tester.pumpWidget(configuredApp(c, p));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      final unfinished = AppPreferences();
      await unfinished.beginOnboarding();
      await tester.pumpWidget(configuredApp(c, unfinished));
      await tester.pumpAndSettle();
      expect(find.byType(FinishSetupPage), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
      unfinished.dispose();
    },
  );
  testWidgets(
    'card view opens canonical password with masking and timed reveal',
    (tester) async {
      final c = SnapshotController();
      await tester.pumpWidget(app(c, const HomeShell()));
      await tester.tap(find.text('卡片').last);
      await tester.pumpAndSettle();
      expect(find.text('测试邮箱'), findsOneWidget);
      expect(find.text('hidden-test-secret'), findsNothing);
      await tester.tap(find.text('测试邮箱'));
      await tester.pumpAndSettle();
      expect(find.byType(CredentialSecretActions), findsOneWidget);
      expect(find.text('hidden-test-secret'), findsNothing);
      await tester.tap(find.text('显示密码 30 秒'));
      await tester.pump();
      expect(find.text('hidden-test-secret'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('hidden-test-secret'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets('desktop uses five rail destinations', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = SnapshotController();
    await tester.pumpWidget(app(c, const HomeShell()));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    await tester.tap(find.text('我的').last);
    await tester.pumpAndSettle();
    expect(find.text('当前身份：资料库所有者'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
  for (final dark in [false, true]) {
    testWidgets('my page and onboarding support 320dp at 200% text ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = SnapshotController();
      final p = AppPreferences();
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: app(c, const HomeShell(), dark: dark, scale: 2),
        ),
      );
      await tester.tap(find.text('我的').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(
        MultiProvider(
          providers: [ChangeNotifierProvider.value(value: p)],
          child: app(c, const OnboardingPage(), dark: dark, scale: 2),
        ),
      );
      await tester.pumpAndSettle();
      for (var i = 0; i < 2; i++) {
        await tester.ensureVisible(find.text('继续'));
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
      p.dispose();
    });
  }
}
