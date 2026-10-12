import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/app_preferences.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/main.dart' as production;
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/workbench/desktop_workbench.dart';
import 'package:live_relay/presentation/workbench/dock_surface.dart';
import 'package:live_relay/presentation/workbench/workbench_card_editor.dart';

/// Run only with XDG_DATA_HOME and TMPDIR inside this explicitly isolated root.
/// The production entrypoint constructs every business service. Secure storage
/// alone uses an empty in-memory store to avoid touching the owner's keyring.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  final rootPath = Platform.environment['LIVERELAY_STARTUP_ROOT'];
  testWidgets(
    'production main onboards a new vault and recreates composition with encrypted desktop edits',
    (tester) async {
      final root = Directory(rootPath!).absolute;
      final support = (await getApplicationSupportDirectory()).absolute;
      final cache = (await getTemporaryDirectory()).absolute;
      expect(support.path.startsWith('${root.path}/'), isTrue);
      expect(cache.path.startsWith('${root.path}/'), isTrue);
      final preferenceFile = File(
        '${support.path}/live_relay/device-preferences.json',
      );
      expect(await preferenceFile.exists(), isFalse);
      expect(
        await Directory('${support.path}/live_relay/vault').exists(),
        isFalse,
      );
      FlutterSecureStorage.setMockInitialValues({});
      AppController? controller;
      AppPreferences? preferences;
      Future<void> until(bool Function() ready) async {
        final end = DateTime.now().add(const Duration(seconds: 60));
        while (!ready() && DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          ready(),
          isTrue,
          reason: 'production screen did not become ready',
        );
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

      void readOwners() {
        final context = tester.element(find.byType(LiveRelayApp));
        controller = context.read<AppController>();
        preferences = context.read<AppPreferences>();
      }

      try {
        await production.main();
        await until(() => find.text('欢迎使用留灯').evaluate().isNotEmpty);
        readOwners();
        expect(controller!.supportsModernSecurity, isTrue);
        expect(controller!.aiSettings.isConfigured, isFalse);
        await tap(find.text('继续'));
        await tap(find.text('继续'));
        await tap(find.text('创建资料库'));
        await tap(find.text('自定密码'));
        const password = 'public-startup-verification-2026';
        await tester.enterText(field('主密码'), password);
        await tester.enterText(field('再次输入主密码'), password);
        await tap(find.text('我已妥善保存口令'));
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
        expect(controller!.header!.formatVersion, 3);
        await tap(find.text('开始使用'));
        await until(() => find.text('选择你的工作台').evaluate().isNotEmpty);
        await tap(find.text('资料工作台'));
        await until(() => find.byType(DockSurface).evaluate().isNotEmpty);
        expect(find.byType(DesktopWorkbench), findsOneWidget);
        expect(preferences!.desktopPreset, 'library');
        await tap(find.text('新建卡片'));
        await until(() => field('总结').evaluate().isNotEmpty);
        const text = '公开夹具：普通客户端入口创建并自动保存这张草稿';
        await tester.enterText(field('总结').last, text);
        // Save-and-lock must include the current edit, even before debounce.
        expect(controller!.cards.single.content, isNot(text));
        await tester.tap(find.byTooltip('保存并锁定'));
        await until(() => find.text('解锁你的加密资料库').evaluate().isNotEmpty);
        expect(controller!.isUnlocked, isFalse);
        await tester.pumpWidget(const SizedBox());
        controller!.dispose();
        preferences!.dispose();
        controller = null;
        preferences = null;

        // Re-run the actual main composition, not a test controller or snapshot.
        await production.main();
        await until(() => find.text('解锁你的加密资料库').evaluate().isNotEmpty);
        readOwners();
        expect(find.text('欢迎使用留灯'), findsNothing);
        await tester.enterText(field('主密码'), password);
        await tap(find.text('解锁'));
        await until(() => find.byType(DockSurface).evaluate().isNotEmpty);
        expect(find.text('选择你的工作台'), findsNothing);
        expect(preferences!.onboardingComplete, isTrue);
        expect(preferences!.desktopPreset, 'library');
        expect(controller!.cards.single.content, text);
        expect(controller!.cards.single.status, CardStatus.draft);
        expect(controller!.aiSettings.isConfigured, isFalse);
        expect(tester.takeException(), isNull);
        final saved = jsonDecode(await preferenceFile.readAsString()) as Map;
        expect(saved.keys.toSet(), {
          'version',
          'appearance',
          'readingSize',
          'onboardingStarted',
          'onboardingComplete',
          'desktopPreset',
        });
        expect(saved.toString().contains(text), isFalse);
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final evidence = Directory(evidencePath);
          await evidence.create(recursive: true);
          final render = tester.renderObject<RenderRepaintBoundary>(
            find.byType(RepaintBoundary).first,
          );
          final image = await render.toImage();
          try {
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            await File('${evidence.path}/native-production-startup.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
          } finally {
            image.dispose();
          }
        }

        // Exercise bulk deletion through the actual selection and review UI.
        // Earlier source-management verification called the use case directly.
        await tap(find.text('我的资料'));
        await tap(find.text('新建卡片'));
        const secondTitle = '公开批量删除夹具';
        await tester.enterText(field('标题').last, secondTitle);
        await until(
          () => controller!.cards.any((card) => card.title == secondTitle),
        );
        final selectedCards = List<LifeCard>.of(controller!.cards);
        expect(selectedCards, hasLength(2));
        await tap(find.text('我的资料'));
        for (final card in selectedCards) {
          final editor = find.byWidgetPredicate(
            (w) => w is WorkbenchCardEditor && w.card.id == card.id,
          );
          final tile = find.ancestor(of: editor, matching: find.byType(Card));
          final checkbox = find.descendant(
            of: tile,
            matching: find.byType(Checkbox),
          );
          await tester.scrollUntilVisible(
            checkbox,
            350,
            scrollable: find
                .descendant(
                  of: find.byType(DockSurface),
                  matching: find.byType(Scrollable),
                )
                .first,
          );
          await tap(checkbox);
        }
        await tap(find.text('删除 2 张'));
        expect(find.text('删除 2 张卡片？'), findsOneWidget);
        for (final card in selectedCards) {
          expect(find.text('• ${card.title}'), findsOneWidget);
        }
        expect(
          tester
              .widget<CheckboxListTile>(
                find.descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(CheckboxListTile),
                ),
              )
              .value,
          isFalse,
        );
        await tap(find.text('取消'));
        expect(controller!.cards.map((card) => card.id).toSet(), {
          for (final card in selectedCards) card.id,
        });
        expect(controller!.recycledCards, isEmpty);
        await tap(find.text('删除 2 张'));
        await tap(find.text('移入回收区'));
        await until(() => controller!.cards.isEmpty);
        expect(controller!.recycledCards.map((card) => card.id).toSet(), {
          for (final card in selectedCards) card.id,
        });
        await tap(find.byTooltip('回收区'));
        await tap(find.byTooltip('恢复卡片').first);
        await tap(find.byTooltip('恢复卡片').first);
        await until(() => controller!.cards.length == 2);
        expect(controller!.recycledCards, isEmpty);
        expect(controller!.cards.every((card) => card.isDraft), isTrue);
        expect(controller!.cards.any((card) => card.content == text), isTrue);
        await tap(find.widgetWithText(TextButton, '助手'));
        await until(() => preferences!.desktopPreset == 'assistant');
        expect(
          tester.widget<DockSurface>(find.byType(DockSurface)).layout.assistant,
          isTrue,
        );
        await tap(find.byTooltip('工作台布局'));
        await tap(find.text('重新选择起始工作台'));
        await until(() => find.text('选择你的工作台').evaluate().isNotEmpty);
        expect(preferences!.desktopPreset, isNull);
        await tap(find.text('资料工作台'));
        await until(() => preferences!.desktopPreset == 'library');
        await tap(find.byTooltip('扩展'));
        expect(
          tester
              .widget<DockSurface>(find.byType(DockSurface))
              .layout
              .containing('extensions'),
          isNotNull,
        );
        await tap(find.byTooltip('工作台布局'));
        await tap(find.text('恢复默认布局'));
        await until(
          () =>
              tester
                  .widget<DockSurface>(find.byType(DockSurface))
                  .layout
                  .containing('extensions') ==
              null,
        );
        expect(preferences!.desktopPreset, 'library');
        expect(controller!.cards.length, 2);
        expect(controller!.cards.any((card) => card.content == text), isTrue);
        // The command shortcut must work while the conversation input has focus.
        await tap(field('对话输入'));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        try {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await until(() => find.byType(Dialog).evaluate().isNotEmpty);
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          '打开扩展',
        );
        await tester.pumpAndSettle();
        expect(find.widgetWithText(ListTile, '打开扩展'), findsOneWidget);
        await tap(find.widgetWithText(ListTile, '打开扩展'));
        expect(
          tester
              .widget<DockSurface>(find.byType(DockSurface))
              .layout
              .containing('extensions'),
          isNotNull,
        );
        expect(tester.takeException(), isNull);
        if (evidencePath != null) {
          final evidence = Directory(evidencePath);
          await File('${evidence.path}/production-startup-verification.json')
              .writeAsString(
                const JsonEncoder.withIndent('  ').convert({
                  'productionEntrypoint': 'lib/main.dart',
                  'injectedBusinessServices': false,
                  'isolatedXdgAndTemporaryDirectory': true,
                  'secureStorageInMemoryFixture': true,
                  'privateVaultOrCredentialsRead': false,
                  'microphoneStarted': false,
                  'upstreamRequested': false,
                  'nativeOnboardingAndRecoveryConfirmation': true,
                  'headerVersion': controller!.header!.formatVersion,
                  'initialDesktopPresetRemembered': true,
                  'immediateSaveAndLockPreservedDraft': true,
                  'mainCompositionRecreatedAndPasswordUnlocked': true,
                  'preferencesContainOnlyDeviceOptions': true,
                  'nativeBulkSelectionCountAndObjectReview': true,
                  'cancelBulkDeleteKeepsCards': true,
                  'originalRecycleDefaultUnchecked': true,
                  'nativeBulkDeleteAndRestorePreserveDrafts': true,
                  'nativePresetSwitchRechooseAndResetPreserveCards': true,
                  'commandShortcutFromFocusedInput': true,
                  'wholeGoalComplete': false,
                }),
              );
        }
      } finally {
        if (controller?.isUnlocked == true) await controller!.lock();
        await tester.pumpWidget(const SizedBox());
        controller?.dispose();
        preferences?.dispose();
        FlutterSecureStorage.setMockInitialValues({});
      }
    },
    skip: !Platform.isLinux || rootPath == null,
  );
}
