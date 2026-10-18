import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';

import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/workbench/desktop_workbench.dart';
import 'package:live_relay/presentation/workbench/workbench_sidebar.dart';

/// Windows native verification of the ordinary production entry flow.
///
/// Run with `flutter test integration_test/windows_vault_creation_test.dart -d
/// windows`. The isolated root deliberately lives under `%APPDATA%`: profiles
/// whose application directories carry the Encrypted (EFS) attribute refuse
/// the metadata rename there, which is the platform condition this case
/// covers. Nothing outside the temporary root is read or written.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets('production flow creates an encrypted vault on Windows', (
    tester,
  ) async {
    final appData = Platform.environment['APPDATA'];
    expect(appData, isNotNull, reason: 'Windows verification needs %APPDATA%');
    final sandbox = await Directory(
      '$appData\\liverelay-windows-verification',
    ).create(recursive: true);
    final root = await sandbox.createTemp('run-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    FlutterSecureStorage.setMockInitialValues({});
    final support = Directory('${root.path}\\support');
    final controller = createAppController(support);
    await controller.initialize();
    final preferenceFile = File(
      '${support.path}\\live_relay\\device-preferences.json',
    );
    final preferences = createAppPreferences(preferenceFile);
    await preferences.load(hasExistingVault: false);
    addTearDown(() {
      preferences.dispose();
      controller.dispose();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: controller),
          ChangeNotifierProvider.value(value: preferences),
        ],
        child: RepaintBoundary(key: boundary, child: const LiveRelayApp()),
      ),
    );

    Future<void> shot(String name) async {
      const output = String.fromEnvironment('WINDOWS_VERIFICATION_SCREENSHOTS');
      if (output.isEmpty) return;
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
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

    Future<void> until(bool Function() ready) async {
      final end = DateTime.now().add(const Duration(seconds: 60));
      while (!ready() && DateTime.now().isBefore(end)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(ready(), isTrue, reason: 'screen did not become ready');
      await tester.pumpAndSettle();
    }

    Finder field(String label) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == label,
    );
    Future<void> tap(Finder target) async {
      await tester.ensureVisible(target);
      await tester.pumpAndSettle();
      await tester.tap(target);
      await tester.pumpAndSettle();
    }

    await until(() => find.text('欢迎使用留灯').evaluate().isNotEmpty);
    expect(controller.supportsModernSecurity, isTrue);
    await shot('01-welcome');
    await tap(find.text('继续'));
    await shot('02-appearance');
    await tap(find.text('继续'));
    await tap(find.text('创建资料库'));
    await shot('03-create-vault');
    await tap(find.text('自定密码'));
    const password = 'public-windows-verification-2026';
    await tester.enterText(field('主密码'), password);
    await tester.enterText(field('再次输入主密码'), password);
    await tap(find.text('我已妥善保存口令'));
    await shot('04-create-vault-filled');
    await tap(find.text('创建并进入资料库'));
    await until(() => find.text('保存独立恢复凭证').evaluate().isNotEmpty);
    final recovery = tester
        .widgetList<SelectableText>(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.byType(SelectableText),
          ),
        )
        .single
        .data!;
    await tap(find.text('我已单独保存恢复凭证'));
    await tester.enterText(field('完整回输凭证确认'), recovery);
    await tap(find.text('已确认，继续'));
    await until(() => find.text('开始使用').evaluate().isNotEmpty);
    await shot('05-created');

    expect(controller.header!.formatVersion, 3);
    expect(controller.isUnlocked, isTrue);
    expect(await preferenceFile.exists(), isTrue);
    expect(
      preferences.onboardingStarted,
      isTrue,
      reason: 'onboarding preferences must survive the commit',
    );
    final vault = Directory('${support.path}\\live_relay\\vault');
    expect(await File('${vault.path}\\vault-header.json').exists(), isTrue);
    expect(await File('${vault.path}\\vault.sqlite').exists(), isTrue);
    expect(controller.lastError, isNull);
    expect(tester.takeException(), isNull);

    // Desktop routes the unlocked shell to the workbench.
    await tap(find.text('开始使用'));
    await until(() => find.byType(DesktopWorkbench).evaluate().isNotEmpty);
    await until(() => find.byType(WorkbenchSidebar).evaluate().isNotEmpty);
    await shot('06-workbench');
  });
}
