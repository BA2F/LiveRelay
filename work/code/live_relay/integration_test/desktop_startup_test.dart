import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart'
    show kSecondaryMouseButton, PointerDeviceKind;
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
import 'package:live_relay/presentation/workbench/conversation_view.dart';
import 'package:live_relay/presentation/workbench/desktop_workbench.dart';
import 'package:live_relay/presentation/workbench/workbench_card_editor.dart';
import 'package:live_relay/presentation/workbench/workbench_sidebar.dart';
import 'package:live_relay/presentation/workbench/workbench_tab_strip.dart';

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
        await until(() => find.byType(DesktopWorkbench).evaluate().isNotEmpty);
        await until(() => find.byType(WorkbenchSidebar).evaluate().isNotEmpty);
        await tap(find.byTooltip('新建 (Ctrl+N)'));
        await tap(find.text('信息卡片'));
        await until(() => field('总结').evaluate().isNotEmpty);
        const text = '公开夹具：普通客户端入口创建并自动保存这张草稿';
        await tester.enterText(field('总结').last, text);
        // Save-and-lock must include the current edit, even before debounce.
        expect(controller!.cards.single.content, isNot(text));
        await tester.tap(find.byTooltip('保存并锁定 (Ctrl+L)'));
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
        await until(() => find.byType(DesktopWorkbench).evaluate().isNotEmpty);
        expect(find.text('选择你的工作台'), findsNothing);
        expect(preferences!.onboardingComplete, isTrue);
        expect(controller!.cards.single.content, text);
        expect(controller!.cards.single.status, CardStatus.draft);
        expect(controller!.aiSettings.isConfigured, isFalse);
        expect(tester.takeException(), isNull);
        // 标签随加密库恢复：上次打开的卡片仍是一个标签。
        await until(
          () => find
              .descendant(
                of: find.byType(WorkbenchTabStrip),
                matching: find.text('新卡片'),
              )
              .evaluate()
              .isNotEmpty,
        );
        final saved = jsonDecode(await preferenceFile.readAsString()) as Map;
        expect(saved.keys.toSet(), {
          'version',
          'appearance',
          'readingSize',
          'onboardingStarted',
          'onboardingComplete',
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

        // 通过真实列表右键菜单走一遍回收：直接移入、撤销恢复，再从回收区恢复。
        // 移入回收区是可撤销动作，不再弹确认框。鼠标右键按真实序列模拟：
        // add → down → up → remove，避免测试鼠标状态残留。
        await tap(find.text('全部卡片'));
        Finder inventoryRow() => find.descendant(
          of: find.byType(WorkbenchSidebar),
          matching: find.text('新卡片'),
        );
        Future<void> rightClick(Finder finder) async {
          final location = tester.getCenter(finder);
          final gesture = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
            buttons: kSecondaryMouseButton,
          );
          await gesture.addPointer(location: location);
          await tester.pump();
          await gesture.down(location);
          await tester.pump();
          await gesture.up();
          await gesture.removePointer();
          await tester.pumpAndSettle();
        }

        await rightClick(inventoryRow());
        await tap(find.text('移入回收区'));
        expect(find.byType(AlertDialog), findsNothing);
        await until(() => controller!.cards.isEmpty);
        expect(controller!.recycledCards, hasLength(1));
        await tap(find.text('撤销'));
        await until(() => controller!.cards.length == 1);
        expect(controller!.recycledCards, isEmpty);
        await rightClick(inventoryRow());
        await tap(find.text('移入回收区'));
        await until(() => controller!.cards.isEmpty);
        expect(controller!.recycledCards, hasLength(1));
        await tap(find.text('回收'));
        await rightClick(
          find.descendant(
            of: find.byType(WorkbenchSidebar),
            matching: find.text('新卡片'),
          ),
        );
        await tap(find.text('恢复卡片'));
        await until(() => controller!.cards.length == 1);
        expect(controller!.recycledCards, isEmpty);
        expect(controller!.cards.every((card) => card.isDraft), isTrue);
        // 助手是一个普通标签页。
        await tap(find.byTooltip('新建 (Ctrl+N)'));
        await tap(find.text('助手对话'));
        await until(() => find.byType(ConversationView).evaluate().isNotEmpty);
        // 对话输入聚焦时快捷键仍然生效：Ctrl+P 按标题打开卡片。
        await tap(field('对话输入'));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        try {
          await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
        } finally {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        }
        await until(() => find.byType(Dialog).evaluate().isNotEmpty);
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          '新卡片',
        );
        await tester.pumpAndSettle();
        await tap(find.widgetWithText(ListTile, '新卡片').last);
        await until(
          () => tester
              .widgetList<WorkbenchCardEditor>(find.byType(WorkbenchCardEditor))
              .any((editor) => editor.card.id == controller!.cards.single.id),
        );
        // 左栏可收起再展开。
        await tap(find.byTooltip('收起左栏 (Ctrl+B)'));
        expect(find.byType(WorkbenchSidebar), findsNothing);
        await tap(find.byTooltip('展开左栏 (Ctrl+B)'));
        expect(find.byType(WorkbenchSidebar), findsOneWidget);
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
                  'immediateSaveAndLockPreservedDraft': true,
                  'mainCompositionRecreatedAndPasswordUnlocked': true,
                  'tabsRestoredAfterUnlock': true,
                  'preferencesContainOnlyDeviceOptions': true,
                  'nativeRecycleMenuReviewAndCancel': true,
                  'originalRecycleDefaultUnchecked': true,
                  'nativeRecycleAndRestorePreserveDrafts': true,
                  'quickOpenShortcutFromFocusedInput': true,
                  'sidebarCollapseToggle': true,
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
