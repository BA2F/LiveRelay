import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/application/app_preferences.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/presentation/app.dart';

import '../test/support/verification_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'desktop foundation uses real encrypted vault and persisted preferences',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'relay-desktop-check-',
      );
      final c = createAppController(
        directory,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = createAppPreferences(
        File('${directory.path}/device-preferences.json'),
      );
      final boundary = GlobalKey();
      const password = 'desktop-verification-only-2026';
      Future<void> shot(String name) async {
        const output = String.fromEnvironment('FOUNDATION_SCREENSHOTS');
        if (output.isEmpty) return;
        await tester.pumpAndSettle();
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/$name.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      }

      try {
        await c.initialize();
        await p.load(hasExistingVault: false);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(key: boundary, child: const LiveRelayApp()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('欢迎使用留灯'), findsOneWidget);
        await shot('01-first-use');
        await tester.tap(find.text('继续'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('深色'));
        await tester.pumpAndSettle();
        await shot('02-appearance');
        await p.beginOnboarding();
        await c.setupVault(password: password, usesChinesePassphrase: false);
        await tester.pumpAndSettle();
        expect(find.text('准备好了'), findsOneWidget);
        await tester.tap(find.text('开始使用'));
        await tester.pumpAndSettle();
        await c.createCard(
          const CardDraft(
            title: '备用钥匙',
            content: '玄关柜第二层',
            kind: CardKind.location,
          ),
        );
        await c.saveCredential(
          const CredentialDraft(
            title: '演示邮箱',
            username: 'example@example.invalid',
            secret: 'fixture-only-secret',
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NavigationRail), findsOneWidget);
        await shot('03-desktop-records');
        await tester.tap(find.text('拍照'));
        await tester.pumpAndSettle();
        expect(find.text('此设备暂不支持'), findsOneWidget);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('卡片').last);
        await tester.pumpAndSettle();
        expect(find.text('演示邮箱'), findsOneWidget);
        expect(find.text('fixture-only-secret'), findsNothing);
        await shot('04-unified-cards');
        await tester.tap(find.text('我的').last);
        await tester.pumpAndSettle();
        expect(find.text('当前身份：资料库所有者'), findsOneWidget);
        await shot('05-my-page');
        await tester.tap(find.text('浅色'));
        await tester.pumpAndSettle();
        await shot('06-my-light');
        final reloaded = createAppPreferences(
          File('${directory.path}/device-preferences.json'),
        );
        await reloaded.load(hasExistingVault: true);
        expect(reloaded.appearance, AppearanceMode.light);
        expect(reloaded.onboardingComplete, isTrue);
        reloaded.dispose();
        await c.lock();
        await tester.pumpAndSettle();
        expect(find.text('从加密备份恢复'), findsOneWidget);
        await c.unlockWithPassword(password);
        await tester.pumpAndSettle();
        expect(c.findInformationCards(''), hasLength(2));
        final archive = await c.exportVault(password);
        try {
          final preview = await c.inspectBackup(archive, password);
          expect(preview.originals, 0);
        } finally {
          archive.fillRange(0, archive.length, 0);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (c.isUnlocked) await c.lock();
        c.dispose();
        p.dispose();
        await directory.delete(recursive: true);
      }
    },
  );
}
