import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_preferences.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/presentation/workbench/conversation_view.dart';
import 'package:live_relay/presentation/workbench/relations_view.dart';
import 'package:live_relay/application/workbench/workbench_layout.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/workbench/dock_surface.dart';

import '../test/support/verification_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'native desktop edits and layout persist in encrypted vault without confirming drafts',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-workbench-test-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = AppPreferences(File('${root.path}/device-preferences.json'));
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-workbench-2026',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '虚构资料位置',
            content: '蓝色文件夹',
            status: CardStatus.draft,
          ),
        );
        final id = c.cards.single.id;
        await p.finishOnboarding();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: const LiveRelayApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('选择你的工作台'), findsOneWidget);
        await tester.tap(find.text('资料工作台'));
        await tester.pumpAndSettle();
        final summary = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '总结',
        );
        await tester.enterText(summary.first, '编辑后仍待确认');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(c.cards.single.content, '编辑后仍待确认');
        expect(c.cards.single.status, CardStatus.draft);
        expect(await c.cardHistory(id), hasLength(2));
        await tester.ensureVisible(find.byTooltip('在新标签编辑').first);
        await tester.tap(find.byTooltip('在新标签编辑').first);
        await tester.pumpAndSettle();
        final surface = tester.widget<DockSurface>(find.byType(DockSurface));
        final cardTab = surface.layout.groups
            .expand((g) => g.tabs)
            .firstWhere((v) => v.startsWith('card/'));
        surface.layout.move(
          cardTab,
          surface.layout.groups.last.id,
          DockPlacement.center,
        );
        await tester.pumpAndSettle();
        expect(summary, findsNWidgets(2));
        await tester.enterText(summary.last, '两个视图一致');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        for (final field in tester.widgetList<TextField>(summary)) {
          expect(field.controller!.text, '两个视图一致');
        }
        await tester.tap(find.byTooltip('确认当前卡片').last);
        await tester.pumpAndSettle();
        expect(c.cards.single.status, CardStatus.confirmed);
        expect(
          (await c.releasePolicy('card', id)).visibleAt(LifeState.deceased),
          VisibilityLevel.hidden,
        );
        surface.layout.move('changes', '', DockPlacement.floating);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        final state = await c.readWorkbenchState();
        expect(state, contains('floating'));
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final dir = Directory(evidencePath);
          await dir.create(recursive: true);
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${dir.path}/native-workbench.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-workbench-2026');
        expect(c.cards.single.content, '两个视图一致');
        expect(await c.readWorkbenchState(), state);
        expect(await c.cardHistory(id), hasLength(4));
        await c.trashCard(id);
        await c.restoreCard(id);
        expect(c.cards.single.content, '两个视图一致');
        final deviceText = await File('${root.path}/device-preferences.json')
            .readAsString();
        expect(deviceText, isNot(contains(id)));
        expect(deviceText, isNot(contains('两个视图一致')));
        if (evidencePath != null) {
          await File('$evidencePath/verification.json').writeAsString(
            jsonEncode({
              'platform': Platform.operatingSystem,
              'fixture': true,
              'autosaveDraft': true,
              'sharedEdit': true,
              'confirmationDoesNotGrantRelease': true,
              'encryptedReopen': true,
              'layoutPersistence': true,
              'revisions': 4,
              'recycleRestore': true,
            }),
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native extension discovery, enable/disable, commands, remove and encrypted persistence',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-extension-test-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = AppPreferences();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-extension-2026',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '扩展待确认卡片',
            content: '虚构待确认摘要',
            status: CardStatus.draft,
          ),
        );
        await c.createCard(
          const CardDraft(title: '扩展已确认卡片', content: '虚构已确认摘要'),
        );
        await p.finishOnboarding();
        await p.setDesktopPreset('library');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: const LiveRelayApp(),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('扩展'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('安装'));
        await tester.tap(find.text('安装'));
        await tester.pumpAndSettle();
        expect(
          await c.readWorkbenchExtensions(),
          contains('liverelay.draft-review'),
        );
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        expect(await c.readWorkbenchExtensions(), contains('"enabled":false'));
        await tester.tap(find.byType(Switch).first);
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('命令面板 · Ctrl+Shift+P'));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.byType(TextField),
          ),
          '待确认审阅',
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(Dialog),
            matching: find.text('打开待确认审阅'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('扩展待确认卡片'), findsOneWidget);
        expect(find.text('扩展已确认卡片'), findsNothing);
        await tester.tap(find.byTooltip('扩展'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('移除扩展'));
        await tester.pumpAndSettle();
        expect(
          await c.readWorkbenchExtensions(),
          '{"version":1,"extensions":[]}',
        );
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-extension-2026');
        expect(
          await c.readWorkbenchExtensions(),
          '{"version":1,"extensions":[]}',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native shared original management keeps bytes and history recoverable',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-source-test-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = AppPreferences();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-source-2026',
          usesChinesePassphrase: false,
        );
        final original = await c.importOriginal(
          bytes: utf8.encode('fictional-original-bytes'),
          originalName: '虚构原件.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        final blob = c.blobs.single;
        await c.createCard(
          const CardDraft(
            title: '共享来源摘要',
            content: '虚构摘要',
            status: CardStatus.draft,
          ),
        );
        final other = c.cards.firstWhere((card) => card.id != original.id);
        await p.finishOnboarding();
        await p.setDesktopPreset('library');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: const LiveRelayApp(),
          ),
        );
        await tester.pumpAndSettle();
        final surface = tester.widget<DockSurface>(find.byType(DockSurface));
        surface.layout.open('card/${other.id}/source-fixture');
        await tester.pumpAndSettle();
        await tester.tap(find.text('管理原件引用'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('虚构原件.txt'));
        await tester.pumpAndSettle();
        expect(
          (await c.currentCardSources(other.id))
              .any((source) => source.blobId == blob.id),
          isTrue,
        );
        await tester.tap(find.text('虚构原件.txt'));
        await tester.pumpAndSettle();
        expect(
          (await c.currentCardSources(other.id))
              .any((source) => source.blobId == blob.id),
          isFalse,
        );
        expect(
          (await c.previewCardDeletion([original.id]))
              .protectedOriginals
              .single
              .id,
          blob.id,
        );
        await c.restoreCardRevision(other.id, 2);
        await c.trashCards([
          original.id,
          other.id,
        ], recycleUnsharedOriginals: true);
        expect(c.recycledBlobIds, contains(blob.id));
        final retained = await c.readOriginal(blob.id);
        expect(utf8.decode(retained), 'fictional-original-bytes');
        retained.fillRange(0, retained.length, 0);
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-source-2026');
        expect(c.recycledBlobIds, contains(blob.id));
        await c.restoreCard(other.id);
        expect(c.recycledBlobIds, isEmpty);
        expect(
          (await c.currentCardSources(other.id))
              .any((source) => source.blobId == blob.id),
          isTrue,
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native continuous conversation edits, consent, confirmation and encrypted recovery',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-conversation-test-',
      );
      final ai = RecordingConversationAi();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        TestAiSettings()..configured = true,
      );
      final p = AppPreferences();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-conversation-2026',
          usesChinesePassphrase: false,
        );
        await p.finishOnboarding();
        await p.setDesktopPreset('assistant');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: const LiveRelayApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final view = tester.widget<ConversationView>(
          find.byType(ConversationView),
        );
        final conversation = view.conversation;
        Future<void> settleConversation() async {
          for (
            var attempt = 0;
            attempt < 100 && conversation.working;
            attempt++
          ) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.pumpAndSettle();
          expect(conversation.working, false);
          expect(conversation.error, isNull);
        }

        final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '对话输入',
        );
        await tester.enterText(input, '虚构秘密');
        conversation.mark(0, SensitiveFieldKind.secret);
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(ai.requests, isEmpty); // UI consent precedes any request.
        expect(find.textContaining('[[TURN1_SECRET_01]]'), findsWidgets);
        expect(
          find.text('允许本次发送'),
          findsOneWidget,
          reason:
              '输入=${conversation.draft}; 错误=${conversation.error}; 提示=${tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text))).map((t) => t.data).join()}',
        );
        await tester.tap(find.text('允许本次发送'));
        await tester.pump(const Duration(milliseconds: 100));
        await settleConversation();
        expect(ai.requests.single.redactedText, '[[TURN1_SECRET_01]]');
        expect(c.cards, isEmpty);
        expect(
          identical(
            tester
                .widget<ConversationView>(find.byType(ConversationView))
                .conversation,
            conversation,
          ),
          true,
        );
        expect(tester.widget<TextField>(input).enabled, true);
        await tester.tap(input);
        await tester.pumpAndSettle();
        await tester.enterText(input, '请整理成卡片');
        expect(tester.widget<TextField>(input).controller!.text, '请整理成卡片');
        expect(conversation.draft, '请整理成卡片');
        await tester.pumpAndSettle();
        expect(conversation.draft, '请整理成卡片');
        expect(conversation.working, false);
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(
          find.text('允许本次发送'),
          findsOneWidget,
          reason:
              '输入=${conversation.draft}; 错误=${conversation.error}; 提示=${tester.widgetList<Text>(find.descendant(of: find.byType(SnackBar), matching: find.byType(Text))).map((t) => t.data).join()}',
        );
        await tester.tap(find.text('允许本次发送'));
        await tester.pump(const Duration(milliseconds: 100));
        await settleConversation();
        expect(ai.turns.last, hasLength(2));
        expect(jsonEncode(ai.turns.last), isNot(contains('虚构秘密')));
        expect(
          conversation.messages.last.suggestions.single.content,
          contains('虚构秘密'),
        );
        expect(c.cards, isEmpty);
        final title = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '建议标题',
        );
        await tester.ensureVisible(title);
        await tester.pumpAndSettle();
        await tester.tap(title);
        await tester.pumpAndSettle();
        await tester.enterText(title, '本人修改后的建议');
        final type = find.byWidgetPredicate(
          (w) => w is DropdownButtonFormField<CardKind>,
        );
        await tester.ensureVisible(type);
        await tester.pumpAndSettle();
        await tester.tap(type);
        await tester.pumpAndSettle();
        await tester.tap(find.text('位置').last);
        await tester.pumpAndSettle();
        final tags = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '建议标签',
        );
        await tester.ensureVisible(tags);
        await tester.pumpAndSettle();
        await tester.tap(tags);
        await tester.pumpAndSettle();
        await tester.enterText(tags, '家中，核对');
        await tester.pumpAndSettle();
        final confirm = find.text('确认并保存 1 张卡片');
        await tester.ensureVisible(confirm);
        await tester.tap(confirm);
        await settleConversation();
        expect(c.cards.single.title, '本人修改后的建议');
        expect(c.cards.single.kind, CardKind.location);
        expect(c.cards.single.tags, containsAll(['家中', '核对']));
        final source = (await c.cardSources(c.cards.single.id)).single;
        expect(source.excerpt, contains('虚构秘密'));
        expect(source.excerpt, contains('请整理成卡片'));
        expect(c.cards.single.status, CardStatus.confirmed);
        expect(
          (await c.releasePolicy(
            'card',
            c.cards.single.id,
          )).visibleAt(LifeState.deceased),
          VisibilityLevel.hidden,
        );
        expect(conversation.messages.last.accepted, true);
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidencePath/native-agent.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        conversation.updateDraft('重开后继续的输入');
        expect(
          await WidgetsBinding.instance.handleRequestAppExit(),
          ui.AppExitResponse.exit,
        );
        expect(await c.readConversationState(), contains('重开后继续的输入'));
        final surface = tester.widget<DockSurface>(find.byType(DockSurface));
        surface.layout.open('speech');
        await tester.pumpAndSettle();
        expect(find.text('另存录音原件到资料库'), findsOneWidget);
        final transcript = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '检查或修改识别文字',
        );
        await tester.enterText(transcript, '虚构转写回填');
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('填入助手输入'));
        await tester.tap(find.text('填入助手输入'));
        await tester.pumpAndSettle();
        expect(conversation.draft, contains('虚构转写回填'));
        expect(ai.requests.length, 2);
        await conversation.flush();
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-conversation-2026');
        final restored = AgentConversation(c);
        await restored.load();
        expect(restored.messages.length, 4);
        expect(restored.messages.last.accepted, true);
        expect(restored.messages.last.suggestions.single.title, '本人修改后的建议');
        expect(restored.draft, '重开后继续的输入\n虚构转写回填');
        await restored.accept(restored.messages.last);
        expect(c.cards.length, 1);
        ai.invalidReply = true;
        final ok = await restored.send(restored.prepare('下一轮', []));
        expect(ok, false);
        expect(restored.messages.length, 4);
        expect(restored.error, contains('未知'));
        restored.dispose();
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native attachment drop handler previews removes encrypts and sends real content',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-attachment-test-',
      );
      final ai = RecordingConversationAi();
      final settings = TestAiSettings()
        ..configured = true
        ..images = true;
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        settings,
      );
      final p = AppPreferences();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-attachment-2026',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(title: '虚构附件卡片', content: '明确选择的卡片正文'),
        );
        await p.finishOnboarding();
        await p.setDesktopPreset('assistant');
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawColor(Colors.green, BlendMode.src);
        final picture = recorder.endRecording();
        final image = await picture.toImage(32, 32);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        final file = File('${root.path}/fictional-photo.png');
        await file.writeAsBytes(png!.buffer.asUint8List());
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: const LiveRelayApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final q = tester
            .widget<ConversationView>(find.byType(ConversationView))
            .conversation;
        Future<void> settle(bool Function() predicate) async {
          for (var i = 0; i < 100 && !predicate(); i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          await tester.pumpAndSettle();
          expect(predicate(), true);
        }

        final drop = tester.widget<DropTarget>(find.byType(DropTarget));
        drop.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await settle(() => q.attachments.length == 1);
        expect(find.text('fictional-photo.png'), findsWidgets);
        expect(c.blobs, isEmpty);
        final firstBytes = q.attachments.single.bytes;
        await tester.ensureVisible(find.byTooltip('移除附件'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('移除附件'));
        await tester.pumpAndSettle();
        expect(q.attachments, isEmpty);
        expect(firstBytes.every((b) => b == 0), true);
        expect(await file.length(), greaterThan(0));
        drop.onDragDone!(
          DropDoneDetails(
            files: [DropItemFile(file.path)],
            localPosition: Offset.zero,
            globalPosition: Offset.zero,
          ),
        );
        await settle(() => q.attachments.length == 1);
        await tester.ensureVisible(find.text('引用卡片'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('引用卡片'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.text('虚构附件卡片'),
          ),
        );
        await tester.pumpAndSettle();
        expect(q.attachments.length, 2);
        expect(c.blobs, isEmpty);
        await q.flush();
        final restored = AgentConversation(c);
        await restored.load();
        expect(restored.attachments.length, 2);
        expect(restored.attachments.first.bytes, await file.readAsBytes());
        restored.dispose();
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final screenshot = await boundary.toImage();
          final data = await screenshot.toByteData(
            format: ui.ImageByteFormat.png,
          );
          await File('$evidencePath/native-attachments.png')
              .writeAsBytes(data!.buffer.asUint8List());
          screenshot.dispose();
        }
        await tester.ensureVisible(find.text('发送'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(ai.requests, isEmpty);
        expect(find.text('附件将以完整内容发送，敏感行标记仅适用于主输入文字：'), findsOneWidget);
        await tester.tap(find.text('允许本次发送'));
        await tester.pump(const Duration(milliseconds: 100));
        await settle(() => !q.working && ai.requests.isNotEmpty);
        expect(q.error, isNull);
        final content = ai.requests.single.inputContent!;
        expect(content.any((p) => p['type'] == 'image_url'), true);
        expect(
          content.any(
            (p) =>
                p['type'] == 'text' &&
                (p['text'] as String).contains('明确选择的卡片正文'),
          ),
          true,
        );
        expect(q.attachments, isEmpty);
        expect(q.messages.first.attachments.length, 2);
        expect(c.blobs, isEmpty);
        await tester.ensureVisible(find.text('另存原件'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('另存原件'));
        await settle(() => !q.working && c.blobs.length == 1);
        expect(q.messages.first.attachments.first.blobId, c.blobs.single.id);
        await q.flush();
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-attachment-2026');
        final reopened = AgentConversation(c);
        await reopened.load();
        expect(
          reopened.messages.first.attachments.first.blobId,
          c.blobs.single.id,
        );
        reopened.dispose();
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native graph separates references shared sources and tags and follows backlinks',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-relations-test-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = AppPreferences();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-relations-2026',
          usesChinesePassphrase: false,
        );
        await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional graph original')),
          originalName: 'fictional-graph.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        final blob = c.blobs.single;
        await c.createCard(
          const CardDraft(title: '虚构图A', content: 'A', tags: ['同标签']),
        );
        final a = c.cards.first.id;
        await c.createCard(
          const CardDraft(title: '虚构图B', content: 'B', tags: ['同标签']),
        );
        final b = c.cards.first.id;
        await c.createCard(
          const CardDraft(title: '仅同标签的C', content: 'C', tags: ['同标签']),
        );
        await c.setCardOriginals(a, [blob.id]);
        await c.setCardOriginals(b, [blob.id]);
        await c.setCardReferences(a, [b]);
        await p.finishOnboarding();
        await p.setDesktopPreset('library');
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: const LiveRelayApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final layout = tester
            .widget<DockSurface>(find.byType(DockSurface))
            .layout;
        layout.open('relations');
        for (final tab in layout.groups.expand((g) => g.tabs).toList()) {
          if (tab != 'relations') layout.close(tab);
        }
        await tester.pumpAndSettle();
        for (
          var i = 0;
          i < 100 &&
              find.text('5 个节点 · 1 条引用 · 3 条来源 · 0 条收纳').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('5 个节点 · 1 条引用 · 3 条来源 · 0 条收纳'), findsOneWidget);
        final dropdowns = find.descendant(
          of: find.byType(RelationsView),
          matching: find.byType(DropdownButton<String>),
        );
        await tester.tap(dropdowns.first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('虚构图B').last);
        await tester.pumpAndSettle();
        expect(find.text('反向引用 · 1'), findsOneWidget);
        expect(find.text('4 个节点 · 1 条引用 · 3 条来源 · 0 条收纳'), findsOneWidget);
        expect(find.text('仅同标签的C'), findsNothing);
        await tester.tap(dropdowns.last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('卡片引用 →').last);
        await tester.pumpAndSettle();
        expect(find.text('2 个节点 · 1 条引用 · 0 条来源 · 0 条收纳'), findsOneWidget);
        await tester.tap(dropdowns.last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('全部关系').last);
        await tester.pumpAndSettle();
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidencePath/native-relations.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        }
        await tester.tap(
          find.ancestor(
            of: find.descendant(
              of: find.byType(RelationsView),
              matching: find.byIcon(Icons.attach_file),
            ),
            matching: find.byType(FilledButton),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看原件'));
        for (
          var i = 0;
          i < 100 &&
              find
                  .textContaining('fictional graph original')
                  .evaluate()
                  .isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.textContaining('fictional graph original'), findsWidgets);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
