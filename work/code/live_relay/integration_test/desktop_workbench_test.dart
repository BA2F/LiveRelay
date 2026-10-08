import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:live_relay/presentation/widgets/local_media_preview.dart';
import 'package:live_relay/presentation/widgets/local_pdf_preview.dart';
import 'package:live_relay/presentation/pages/originals_page.dart';
import 'package:live_relay/presentation/workbench/attachment_strip.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/presentation/workbench/review_source_view.dart';
import 'package:live_relay/presentation/workbench/workbench_card_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ports/speech_provider.dart';
import 'package:live_relay/infrastructure/speech/http_remote_speech_provider.dart';
import 'package:live_relay/presentation/pages/speech_input_page.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:cross_file/cross_file.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/presentation/workbench/conversation_view.dart';
import 'package:live_relay/presentation/workbench/relations_view.dart';
import 'package:live_relay/application/workbench/workbench_layout.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/workbench/dock_surface.dart';

import '../test/support/verification_fakes.dart';
import '../test/support/pdf_fixture.dart';
import '../test/workbench/remote_speech_test.dart' show wave;
import '../test/workbench/window_speech_bridge_test.dart'
    show FixtureWindowSpeech;
import '../test/workbench/review_action_proposal_test.dart' show PlanningAi;
import '../test/workbench/conversation_concurrency_test.dart'
    show PendingConversationAi;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  WidgetController.hitTestWarningShouldBeFatal = true;
  testWidgets(
    'native M4A prepares full WAV or reviewed transcript and preserves original confirmation evidence',
    _mediaConversionTest,
  );
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
      final p = createAppPreferences(File('${root.path}/device-preferences.json'));
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
        final targetGroup = surface.layout.containing('cards')!;
        final originalGroups = surface.layout.groups.length;
        Future<void> dockDrag(Finder source, DockPlacement placement) async {
          await tester.ensureVisible(source);
          final gesture = await tester.startGesture(tester.getCenter(source));
          await gesture.moveBy(const Offset(40, 0));
          await tester.pump();
          final target = find.byKey(
            ValueKey('dock-target-${targetGroup.id}-${placement.name}'),
          );
          expect(target, findsOneWidget);
          await gesture.moveTo(tester.getCenter(target));
          await tester.pump();
          final highlight = tester.widget<Container>(
            find.descendant(of: target, matching: find.byType(Container)).first,
          );
          expect(
            (highlight.decoration! as BoxDecoration).color,
            Theme.of(tester.element(target)).colorScheme.primaryContainer,
          );
          await gesture.up();
          await tester.pumpAndSettle();
        }

        Finder viewDrag(bool tab) => find
            .byWidgetPredicate(
              (w) => w is Draggable<String> && w.data == 'changes',
            )
            .at(tab ? 1 : 0);
        for (final placement in [
          DockPlacement.left,
          DockPlacement.right,
          DockPlacement.top,
          DockPlacement.bottom,
        ]) {
          await dockDrag(viewDrag(false), placement);
          expect(surface.layout.groups.length, originalGroups + 1);
          expect(
            surface.layout.containing('changes')!.id,
            isNot(targetGroup.id),
          );
          await dockDrag(viewDrag(true), DockPlacement.center);
          expect(surface.layout.containing('changes')!.id, targetGroup.id);
          expect(surface.layout.groups.length, originalGroups);
        }
        final split = surface.layout.root as DockSplit;
        final fraction = split.fraction;
        await tester.drag(find.byKey(ObjectKey(split)), const Offset(35, 0));
        await tester.pumpAndSettle();
        expect(split.fraction, greaterThan(fraction));
        await tester.tap(find.byTooltip('移动当前视图').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('工作台内浮动').last);
        await tester.pumpAndSettle();
        final floating = surface.layout.floating.single;
        final oldPosition = Offset(floating.x, floating.y);
        await tester.drag(
          find.byKey(ValueKey('dock-floating-move-${floating.group.id}')),
          const Offset(35, 25),
        );
        await tester.pumpAndSettle();
        expect(floating.x, greaterThan(oldPosition.dx));
        expect(floating.y, greaterThan(oldPosition.dy));
        final oldSize = Size(floating.width, floating.height);
        await tester.drag(
          find.byKey(ValueKey('dock-floating-resize-${floating.group.id}')),
          const Offset(-45, -35),
        );
        await tester.pumpAndSettle();
        expect(floating.width, lessThan(oldSize.width));
        expect(floating.height, lessThan(oldSize.height));
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
              'nativePointerDocking': [
                'left',
                'right',
                'top',
                'bottom',
                'center',
              ],
              'dropHighlight': true,
              'iconAndTabDrag': true,
              'splitResize': true,
              'floatingMoveResize': true,
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
      final p = createAppPreferences();
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
      final p = createAppPreferences();
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
      final p = createAppPreferences();
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
      final p = createAppPreferences();
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
        expect(
          find.text('请核对每个附件的实际发送范围。敏感行标记仅适用于主输入，附件及核对转写不会自动替换敏感内容：'),
          findsOneWidget,
        );
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
      final p = createAppPreferences();
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
  testWidgets(
    'native provider/model choice protects current conversation and settings survive reopening',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'liverelay-profiles-native-',
      );
      final store = AiProviderSettingsStore();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingConversationAi(),
        store,
      );
      final p = createAppPreferences();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-profiles-password',
          usesChinesePassphrase: false,
        );
        await c.saveAiSettings(
          name: '服务甲',
          endpoint: 'https://a.invalid/chat',
          model: '模型甲',
          models: ['模型甲', '模型甲二'],
          apiKey: 'fixture-key-a',
        );
        final first = c.aiSettings.id;
        await c.saveAiSettings(
          name: '服务乙',
          create: true,
          endpoint: 'https://b.invalid',
          model: '模型乙',
          models: ['模型乙'],
          apiKey: 'fixture-key-b',
          protocol: AiProtocol.responses,
        );
        await c.selectAiProfile(first, '模型甲');
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
        final conversation = tester
            .widget<ConversationView>(find.byType(ConversationView))
            .conversation;
        conversation.updateDraft('仅给甲服务的虚构内容');
        final selector = find.byKey(const ValueKey('conversation-model'));
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('服务乙 · 模型乙').last);
        await tester.pumpAndSettle();
        expect(find.text('切换服务或模型？'), findsOneWidget);
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect(c.aiSettings.id, first);
        expect(conversation.draft, '仅给甲服务的虚构内容');
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('服务乙 · 模型乙').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('切换并开始新会话'));
        await tester.pumpAndSettle();
        expect(c.aiSettings.name, '服务乙');
        expect(c.aiSettings.protocol, AiProtocol.responses);
        expect(c.aiSettings.endpoint, 'https://b.invalid/responses');
        expect(conversation.draft, isEmpty);
        expect(conversation.messages, isEmpty);
        expect(await store.readApiKey(), 'fixture-key-b');
        expect((await AiProviderSettingsStore().read()).name, '服务乙');
        await tester.tap(find.byTooltip('AI 服务设置'));
        await tester.pumpAndSettle();
        expect(find.text('编辑服务配置'), findsOneWidget);
        await tester.tap(find.text('添加另一个服务'));
        await tester.pumpAndSettle();
        final name = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '服务名称',
        );
        await tester.enterText(name, '服务丙');
        final endpoint = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText == 'HTTPS 服务地址（Chat Completions）',
        );
        await tester.enterText(endpoint, 'https://c.invalid/v1/');
        await tester.pump();
        expect(
          find.text('实际请求：https://c.invalid/v1/chat/completions'),
          findsOneWidget,
        );
        final model = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '模型名称',
        );
        await tester.enterText(model, '模型丙');
        final key = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '服务密钥',
        );
        await tester.ensureVisible(key);
        await tester.pumpAndSettle();
        await tester.enterText(key, 'fixture-key-c');
        await tester.tap(find.text('安全保存'));
        await tester.pumpAndSettle();
        expect(c.aiProfiles.length, 3);
        expect(c.aiSettings.name, '服务丙');
        expect(c.aiSettings.endpoint, 'https://c.invalid/v1/chat/completions');
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (screenshotKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-providers.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
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
    'native remote speech configuration, per-upload consent and transcript backfill keep recording storage separate',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final root = await Directory.systemTemp.createTemp(
        'liverelay-remote-speech-native-',
      );
      final file = await File('${root.path}/fixture.wav').writeAsBytes(wave());
      final oldPicker = FilePickerPlatform.instance;
      FilePickerPlatform.instance = _FixturePicker(
        file.path,
        await file.length(),
      );
      var requests = 0;
      final remote = HttpRemoteSpeechProvider(
        client: MockClient((r) async {
          requests++;
          expect(r.url.host, 'asr.invalid');
          return http.Response(
            '{"text":"虚构远程转写"}',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      final speech = createSpeechService(
        _NoSpeechModel(),
        supported: true,
        remoteProvider: remote,
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
        null,
        null,
        null,
        speech,
      );
      String? backfill;
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-speech-password',
          usesChinesePassphrase: false,
        );
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: c,
            child: MaterialApp(
              home: RepaintBoundary(
                key: screenshotKey,
                child: SpeechInputPage(onTranscript: (v) => backfill = v),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('远程语音服务设置'));
        await tester.pumpAndSettle();
        Future<void> enter(String label, String text) async {
          final field = find.byWidgetPredicate(
            (w) => w is TextField && w.decoration?.labelText == label,
          );
          await tester.enterText(field, text);
        }

        await enter('语音服务名称', '独立语音甲');
        await enter('HTTPS 音频转写地址', 'https://asr.invalid/audio/transcriptions');
        await enter('语音识别模型', 'fixture-transcription');
        await enter('语音密钥', 'fixture-native-key');
        await tester.tap(find.text('安全保存'));
        await tester.pumpAndSettle();
        expect(speech.usingRemote, false);
        final selector = find.byType(DropdownButtonFormField<bool>);
        await tester.tap(selector);
        await tester.pumpAndSettle();
        await tester.tap(find.text('远程语音服务').last);
        await tester.pumpAndSettle();
        expect(speech.usingRemote, true);
        await tester.tap(find.text('识别音频／视频音轨'));
        for (
          var i = 0;
          i < 100 && find.text('允许上传本次音频？').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          find.text('允许上传本次音频？'),
          findsOneWidget,
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        await tester.tap(find.text('取消').last);
        await tester.pumpAndSettle();
        expect(requests, 0);
        expect(c.blobs, isEmpty);
        await tester.tap(find.text('识别音频／视频音轨'));
        for (
          var i = 0;
          i < 100 && find.text('允许上传本次音频？').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(find.text('允许本次音频上传'));
        final transcript = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '检查或修改识别文字',
        );
        for (var i = 0; i < 100; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (tester.widget<TextField>(transcript).controller!.text ==
              '虚构远程转写') {
            break;
          }
        }
        expect(requests, 1);
        expect(tester.widget<TextField>(transcript).controller!.text, '虚构远程转写');
        expect(c.blobs, isEmpty);
        expect(c.cards, isEmpty);
        await tester.ensureVisible(find.text('填入助手输入'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('填入助手输入'));
        await tester.pumpAndSettle();
        expect(backfill, '虚构远程转写');
        expect(requests, 1);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (screenshotKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-remote-speech.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        remote.close();
        FilePickerPlatform.instance = oldPicker;
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native Linux decrypts audio/video, renders frames, seeks, pauses and clears playback on lock',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-media-native-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final audioKey = GlobalKey<LocalMediaPreviewState>();
      final videoKey = GlobalKey<LocalMediaPreviewState>();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-media-password',
          usesChinesePassphrase: false,
        );
        final audioPath = '${root.path}/fixture.wav';
        final videoPath = '${root.path}/fixture.mp4';
        final wav = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'sine=frequency=440:sample_rate=16000',
          '-t',
          '3',
          '-ac',
          '1',
          '-c:a',
          'pcm_s16le',
          audioPath,
        ]);
        final mp4 = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=red:s=160x90:r=24',
          '-t',
          '3',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          videoPath,
        ]);
        expect(wav.exitCode, 0);
        expect(mp4.exitCode, 0);
        final audio = await c.importOriginal(
          bytes: await File(audioPath).readAsBytes(),
          originalName: 'fixture.wav',
          mimeType: 'audio/wav',
          mediaKind: BlobMediaKind.audio,
        );
        final audioId = (await c.currentCardSources(audio.id)).single.blobId!;
        final video = await c.importOriginal(
          bytes: await File(videoPath).readAsBytes(),
          originalName: 'fixture.mp4',
          mimeType: 'video/mp4',
          mediaKind: BlobMediaKind.video,
        );
        final videoId = (await c.currentCardSources(video.id)).single.blobId!;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: screenshotKey,
                child: Column(
                  children: [
                    LocalMediaPreview(
                      key: audioKey,
                      controller: c,
                      name: 'fixture.wav',
                      video: false,
                      readBytes: () => c.readOriginal(audioId),
                    ),
                    LocalMediaPreview(
                      key: videoKey,
                      controller: c,
                      name: 'fixture.mp4',
                      video: true,
                      compact: true,
                      readBytes: () => c.readOriginal(videoId),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        for (
          var i = 0;
          i < 150 &&
              find.byKey(const ValueKey('local-media-play')).evaluate().length <
                  2;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(
          find.byKey(const ValueKey('local-media-play')),
          findsNWidgets(2),
        );
        final ap = audioKey.currentState!.player!;
        final vp = videoKey.currentState!.player!;
        for (var i = 0; i < 100 && vp.state.width == null; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(vp.state.width, 160);
        expect(vp.state.height, 90);
        expect(ap.state.playing, false);
        expect(vp.state.playing, false);
        await ap.setVolume(0);
        await vp.setVolume(0);
        await tester.tap(find.byKey(const ValueKey('local-media-play')).first);
        for (
          var i = 0;
          i < 100 && ap.state.position.inMilliseconds < 100;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(ap.state.position.inMilliseconds, greaterThanOrEqualTo(100));
        await tester.tap(find.byKey(const ValueKey('local-media-play')).first);
        await tester.pump(const Duration(milliseconds: 200));
        expect(ap.state.playing, false);
        await vp.seek(const Duration(seconds: 1));
        for (
          var i = 0;
          i < 100 && vp.state.position.inMilliseconds < 900;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(vp.state.position.inMilliseconds, greaterThanOrEqualTo(900));
        final frames = await videoKey.currentState!.sampleFrames();
        expect(frames, hasLength(4));
        final frame = frames.first.bytes;
        expect(frame.length, greaterThan(100));
        final audioFile = audioKey.currentState!.temporaryFile!;
        final videoFile = videoKey.currentState!.temporaryFile!;
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (screenshotKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-media.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
          await File('$evidence/media-verification.json').writeAsString(
            jsonEncode({
              'audioDurationMs': ap.state.duration.inMilliseconds,
              'videoDurationMs': vp.state.duration.inMilliseconds,
              'width': vp.state.width,
              'height': vp.state.height,
              'seekMs': vp.state.position.inMilliseconds,
              'frameBytes': frame.length,
              'frameExport': 'bounded-offline-ffmpeg',
              'fixtureOnly': true,
            }),
          );
        }
        for (final f in frames) {
          f.bytes.fillRange(0, f.bytes.length, 0);
        }
        await c.lock();
        for (
          var i = 0;
          i < 100 && (await audioFile.exists() || await videoFile.exists());
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(await audioFile.exists(), false);
        expect(await videoFile.exists(), false);
        expect(audioKey.currentState!.player, isNull);
        expect(videoKey.currentState!.player, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native Agent audio preview and video frame selection send reviewed multimodal content',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-multimodal-native-',
      );
      final provider = RecordingConversationAi();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        provider,
        TestAiSettings()
          ..configured = true
          ..images = true
          ..audio = true,
      );
      final q = AgentConversation(c);
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-multimodal-password',
          usesChinesePassphrase: false,
        );
        final audioFile = await File('${root.path}/fixture.wav')
            .writeAsBytes(wave());
        final videoPath = '${root.path}/fixture.mp4';
        final result = await Process.run('ffmpeg', [
          '-hide_banner',
          '-loglevel',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=blue:s=160x90:r=24',
          '-t',
          '2',
          '-c:v',
          'libx264',
          '-pix_fmt',
          'yuv420p',
          videoPath,
        ]);
        expect(result.exitCode, 0);
        await q.addFilePaths([audioFile.path, videoPath]);
        expect(c.blobs, isEmpty);
        expect(q.attachments.map((a) => a.kind), [
          ConversationAttachmentKind.audio,
          ConversationAttachmentKind.video,
        ]);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: screenshotKey,
                child: ColoredBox(
                  color: Colors.white,
                  child: AnimatedBuilder(
                    animation: q,
                    builder: (_, _) => AttachmentStrip(conversation: q),
                  ),
                ),
              ),
            ),
          ),
        );
        final audio = q.attachments.first;
        final video = q.attachments.last;
        await tester.tap(
          find.byKey(ValueKey('attachment-preview-${audio.id}')),
        );
        for (
          var i = 0;
          i < 100 &&
              find.byKey(const ValueKey('local-media-play')).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('local-media-play')), findsOneWidget);
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('attachment-preview-${video.id}')),
        );
        for (
          var i = 0;
          i < 100 &&
              find.byKey(const ValueKey('local-media-play')).evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.tap(find.text('选取4帧供发送前检查'));
        for (var i = 0; i < 100 && video.frames.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await tester.pumpAndSettle();
        expect(
          video.frames,
          hasLength(4),
          reason: tester
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data)
              .join(' | '),
        );
        expect(
          video.frames.last.milliseconds,
          greaterThan(video.frames.first.milliseconds),
        );
        expect(c.blobs, isEmpty);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (screenshotKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-multimodal.png')
              .writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        }
        final turn = q.prepare('理解这段虚构媒体', []);
        expect(await q.send(turn), true);
        final parts = provider.requests.single.inputContent!;
        expect(parts.where((p) => p['type'] == 'input_audio'), hasLength(1));
        expect(parts.where((p) => p['type'] == 'image_url'), hasLength(4));
        expect(jsonEncode(parts), contains('不发送视频原件'));
        expect(jsonEncode(parts), contains('不发送音轨'));
        expect(q.disclosureHistory, isNot(contains(base64Encode(audio.bytes))));
        expect(q.disclosureHistory, contains('完整音频'));
        await q.flush();
        expect(await c.readConversationState(), contains('frames'));
      } finally {
        await tester.pumpWidget(const SizedBox());
        q.dispose();
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native confirmed source keeps complete image and selected revision after a new conversation',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-confirmed-source-native-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingConversationAi(),
        TestAiSettings(),
      );
      final p = createAppPreferences();
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-review-2026',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(title: '所选虚构卡片', content: '确认前的卡片正文'),
        );
        final selected = c.cards.single;
        await c.createCard(const CardDraft(title: '组合原有成员', content: '虚构成员'));
        final member = c.cards.singleWhere((c) => c.title == '组合原有成员');
        await c.combineCards('本人选择的组合', [selected.id, member.id]);
        final bundle = c.cards.singleWhere((c) => c.kind == CardKind.bundle);
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
        final q = tester
            .widget<ConversationView>(find.byType(ConversationView))
            .conversation;
        q.attachCard(selected);
        final file = File('${root.path}/fixture.png');
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 48, 48),
          Paint()..color = Colors.blue,
        );
        canvas.drawCircle(
          const Offset(24, 24),
          12,
          Paint()..color = Colors.white,
        );
        final picture = recorder.endRecording();
        final fixtureImage = await picture.toImage(48, 48);
        final imageBytes = (await fixtureImage.toByteData(
          format: ui.ImageByteFormat.png,
        ))!.buffer.asUint8List();
        fixtureImage.dispose();
        picture.dispose();
        await file.writeAsBytes(imageBytes);
        await q.addFilePaths([file.path]);
        final chosen = List<ConversationAttachment>.of(q.attachments);
        q.attachments.clear();
        q.messages.add(
          ConversationMessage('user', '完整来源虚构输入', attachments: chosen),
        );
        final reply = ConversationMessage(
          'assistant',
          '虚构模型答复',
          providerLabel: '本地验收 fixture',
          suggestions: [
            const AiCardSuggestion(
              title: '来源验收卡片',
              content: '本人核对的总结',
              kind: CardKind.note,
              isInference: false,
            ),
          ],
        );
        q.messages.add(reply);
        await q.retrySave();
        await tester.pumpAndSettle();
        final operations = find.text('保存时的操作');
        await tester.ensureVisible(operations);
        await tester.pumpAndSettle();
        await tester.tap(operations);
        await tester.pumpAndSettle();
        final collection = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<String> &&
              w.decoration.labelText == '收纳到已有组合',
        );
        await tester.ensureVisible(collection);
        await tester.pumpAndSettle();
        await tester.tap(collection);
        await tester.pumpAndSettle();
        await tester.tap(find.text('本人选择的组合').last);
        await tester.pumpAndSettle();
        final deceased = find.byWidgetPredicate(
          (w) =>
              w is DropdownButtonFormField<VisibilityLevel> &&
              w.decoration.labelText == '身故时可见层级',
        );
        await tester.ensureVisible(deceased);
        await tester.pumpAndSettle();
        await tester.tap(deceased);
        await tester.pumpAndSettle();
        await tester.tap(find.text('正文前80字').last);
        await tester.pumpAndSettle();
        final reference = find.byWidgetPredicate(
          (w) =>
              w is CheckboxListTile &&
              w.title is Text &&
              (w.title as Text).data == selected.title,
        );
        await tester.ensureVisible(reference);
        await tester.pumpAndSettle();
        await tester.tap(reference);
        await tester.pumpAndSettle();
        expect(reply.actions.single.bundleId, bundle.id);
        expect(reply.actions.single.referenceIds, [selected.id]);
        expect(reply.actions.single.deceased, VisibilityLevel.summary);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-review-actions.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        final confirm = find.text('确认并保存 1 张卡片');
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        await tester.tap(confirm);
        for (var i = 0; i < 100 && q.working; i++) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        await tester.pumpAndSettle();
        expect(q.error, isNull);
        final reviewed = c.cards.singleWhere((c) => c.title == '来源验收卡片');
        expect(
          c.cardReferences.any(
            (r) => r.from == reviewed.id && r.to == selected.id,
          ),
          true,
        );
        expect(
          (await c.cardRelations(bundle.id)).any(
            (r) =>
                r.toCardId == reviewed.id &&
                r.kind == RelationKind.bundleMember,
          ),
          true,
        );
        expect(
          (await c.releasePolicy('card', reviewed.id)).deceased,
          VisibilityLevel.summary,
        );
        await q.newConversation();
        await c.updateCard(
          selected.id,
          const CardDraft(title: '所选虚构卡片', content: '后来修改的正文'),
        );
        final surface = tester.widget<DockSurface>(find.byType(DockSurface));
        surface.layout.open('card/${reviewed.id}');
        await tester.pumpAndSettle();
        final editor = find
            .byWidgetPredicate(
              (w) => w is WorkbenchCardEditor && w.card.id == reviewed.id,
            )
            .first;
        await tester.tap(
          find.descendant(of: editor, matching: find.byTooltip('查看确认来源')),
        );
        for (
          var i = 0;
          i < 100 && find.text('完整来源虚构输入').evaluate().isEmpty;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(find.byType(ReviewSourceView), findsOneWidget);
        expect(find.text('完整来源虚构输入'), findsOneWidget);
        final cardAttachment = find.byKey(
          ValueKey('review-attachment-${chosen.first.id}'),
        );
        await tester.ensureVisible(cardAttachment);
        await tester.tap(find.text(chosen.first.name));
        await tester.pumpAndSettle();
        expect(find.text('所选虚构卡片\n确认前的卡片正文'), findsOneWidget);
        await tester.tap(find.text(chosen.first.name));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('fixture.png'));
        await tester.tap(find.text('fixture.png'));
        await tester.pumpAndSettle();
        expect(find.byType(Image), findsWidgets);
        expect(c.blobs, isEmpty);
        if (evidence != null) {
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-review-source.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          await File('$evidence/review-source-verification.json').writeAsString(
            jsonEncode({
              'platform': 'real Flutter Linux',
              'fixtureOnly': true,
              'newConversationCleared': q.messages.isEmpty,
              'originalCardRevisionRetained': selected.revisionNumber,
              'noAutomaticBlobImport': c.blobs.isEmpty,
              'confirmedCard': reviewed.id,
              'imageByteLength': imageBytes.length,
              'planApplied': reply.actions.single.toJson(),
            }),
          );
        }
        final source = (await c.cardReviewSource(reviewed.id))!;
        expect(source.inputs.single.attachments.last.bytes, imageBytes);
        source.wipe();
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-review-2026');
        final reopened = (await c.cardReviewSource(reviewed.id))!;
        expect(reopened.inputs.single.attachments.last.bytes, imageBytes);
        reopened.wipe();
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
    'native structured Agent proposals need owner adoption and show selected target scope',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-native-proposal-',
      );
      final ai = PlanningAi();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        TestAiSettings()..configured = true,
      );
      final q = AgentConversation(c);
      final boundary = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-native-proposal',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '已选家庭组合',
            content: 'fixture bundle',
            kind: CardKind.bundle,
          ),
        );
        final bundle = c.cards.single;
        await c.createCard(
          const CardDraft(title: '已选资料', content: 'fixture information'),
        );
        final reference = c.cards.firstWhere((card) => card.id != bundle.id);
        q.attachCard(bundle);
        q.attachCard(reference);
        q.updateDraft('请建议收纳引用以及身故时正文可见层级');
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: RepaintBoundary(
                key: boundary,
                child: Material(
                  color: Colors.white,
                  child: ConversationView(
                    conversation: q,
                    openManual: () {},
                    openSpeech: () {},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        expect(find.textContaining('供模型提出收纳/引用草案'), findsOneWidget);
        expect(find.textContaining(bundle.id), findsOneWidget);
        await tester.tap(find.text('允许本次发送'));
        await tester.pumpAndSettle();
        final message = q.messages.last;
        expect(message.actions.single.hasChanges, isFalse);
        expect(c.cards.length, 2);
        final adopt = find.byKey(
          ValueKey('adopt-proposal-${message.reviewId}-0'),
        );
        await tester.ensureVisible(adopt);
        await tester.pumpAndSettle();
        expect(find.text('模型操作草案（尚未授权执行）'), findsOneWidget);
        await tester.tap(adopt);
        await tester.pumpAndSettle();
        expect(message.actions.single.bundleId, bundle.id);
        expect(message.actions.single.referenceIds, [reference.id]);
        expect(c.cards.length, 2);
        final confirm = find.text('确认并保存 1 张卡片');
        await tester.ensureVisible(confirm);
        await tester.pumpAndSettle();
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final evidence = await Directory(evidencePath)
              .create(recursive: true);
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${evidence.path}/native-model-plan.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.tap(confirm);
        await tester.pumpAndSettle();
        expect(message.accepted, isTrue);
        final created = c.cards.firstWhere((card) => card.title == '建议卡片');
        expect(c.cardReferences.single.from, created.id);
        expect(c.cardReferences.single.to, reference.id);
        final source = (await c.cardReviewSource(created.id))!;
        expect(source.proposals.single!.plan.bundleId, bundle.id);
        expect(source.actions.single.bundleId, bundle.id);
        source.wipe();
      } finally {
        await tester.pumpWidget(const SizedBox());
        q.dispose();
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native PDF original and attachment render, turn pages and revoke on lock',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-pdf-native-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final q = AgentConversation(c);
      final boundary = GlobalKey();
      Future<LocalPdfPreviewState> ready(int page) async {
        for (var i = 0; i < 150; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          final found = find.byType(LocalPdfPreview);
          if (found.evaluate().length == 1) {
            final state = tester.state<LocalPdfPreviewState>(found);
            if (state.isReady && state.currentPage == page) return state;
          }
        }
        throw StateError(
          'PDF未就绪: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).join(' | ')}',
        );
      }

      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-pdf-password',
          usesChinesePassphrase: false,
        );
        await c.importOriginal(
          bytes: syntheticPdf(),
          originalName: 'fictional.pdf',
          mimeType: 'application/octet-stream', // Earlier desktop imports.
          mediaKind: BlobMediaKind.document,
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundary,
            child: ChangeNotifierProvider.value(
              value: c,
              child: const MaterialApp(home: OriginalsPage()),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('fictional.pdf'));
        final first = await ready(0);
        expect(first.pageCount, 2);
        expect(first.renderedImage!.width, lessThanOrEqualTo(1600));
        final pageOne = await first.renderedImage!.toByteData(
          format: ui.ImageByteFormat.png,
        );
        await tester.ensureVisible(find.byKey(const ValueKey('pdf-next-page')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pdf-next-page')));
        final second = await ready(1);
        final pageTwo = await second.renderedImage!.toByteData(
          format: ui.ImageByteFormat.png,
        );
        expect(
          pageTwo!.buffer.asUint8List(),
          isNot(orderedEquals(pageOne!.buffer.asUint8List())),
        );
        expect(find.text('第 2 / 2 页'), findsOneWidget);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-pdf.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        // Navigation disposes the original preview before attachment preview.
        await tester.pumpWidget(const SizedBox());
        await first.closePreview();
        expect(first.renderedImage, isNull);
        // The desktop source tab and card source panel use InlineOriginal.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: InlineOriginal(controller: c, blobId: c.blobs.single.id),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('查看原件'));
        final inline = await ready(0);
        expect(inline.pageCount, 2);
        await tester.pumpWidget(const SizedBox());
        await inline.closePreview();
        final attachment = ConversationAttachment.read(
          'attachment.pdf',
          syntheticPdf(),
        );
        q.attachments.add(attachment);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: AttachmentTile(attachment: attachment, conversation: q),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(
          find.byKey(ValueKey('attachment-preview-${attachment.id}')),
        );
        final preview = await ready(0);
        expect(preview.pageCount, 2);
        expect(
          c.blobs,
          hasLength(1),
        ); // Preview does not separately save an original.
        await c.lock();
        await tester.pump();
        expect(preview.renderedImage, isNull);
        expect(preview.pageCount, 0);
        expect(find.text('预览已关闭'), findsOneWidget);
        if (evidence != null) {
          await File('$evidence/pdf-verification.json').writeAsString(
            jsonEncode({
              'fixtureOnly': true,
              'engine': 'native PDFium',
              'pages': 2,
              'distinctRenderedPages': true,
              'encryptedOriginalAndAttachment': true,
              'legacyGenericMimeAndDesktopInlineOriginal': true,
              'previewDoesNotSaveAttachmentAsOriginal': true,
              'lockDisposesDocumentAndImage': true,
            }),
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        q.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native workbench autosaves local edits while Agent waits and save-lock cancels reply',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-native-network-',
      );
      final ai = PendingConversationAi();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        TestAiSettings()..configured = true,
      );
      final p = createAppPreferences(File('${root.path}/preferences.json'));
      final boundary = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-native-network',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '虚构边写边问',
            content: '修改前的总结',
            status: CardStatus.draft,
          ),
        );
        await p.finishOnboarding();
        await p.setDesktopPreset('assistant');
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
        final q = tester
            .widget<ConversationView>(find.byType(ConversationView))
            .conversation;
        final input = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '对话输入',
        );
        await tester.enterText(input, '虚构长请求，等待时继续编辑卡片');
        await tester.pumpAndSettle();
        await tester.tap(find.text('发送'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('允许本次发送'));
        for (var i = 0; i < 100 && !ai.entered.isCompleted; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(ai.entered.isCompleted, true);
        expect(q.working, true);
        expect(c.isBusy, false);
        await tester.pump(const Duration(milliseconds: 300));
        final summary = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '总结',
        );
        await tester.enterText(summary, '网络仍在等待，本地自动保存完成');
        for (
          var i = 0;
          i < 100 && c.cards.single.content != '网络仍在等待，本地自动保存完成';
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(c.cards.single.content, '网络仍在等待，本地自动保存完成');
        expect(c.cards.single.status, CardStatus.draft);
        expect(ai.reply.isCompleted, false);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('$evidence/native-network-autosave.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.tap(find.byTooltip('保存并锁定'));
        await tester.pumpAndSettle();
        expect(c.isUnlocked, false);
        expect(ai.requests.single.cancellation!.isCancelled, true);
        ai.complete();
        await tester.pump(const Duration(milliseconds: 300));
        await c.unlockWithPassword('fixture-native-network');
        await tester.pumpAndSettle();
        expect(c.cards.single.content, '网络仍在等待，本地自动保存完成');
        final reopened = tester
            .widget<ConversationView>(find.byType(ConversationView))
            .conversation;
        expect(reopened.messages, isEmpty);
        expect(reopened.draft, '虚构长请求，等待时继续编辑卡片');
        if (evidence != null) {
          await File('$evidence/network-autosave-verification.json')
              .writeAsString(
                jsonEncode({
                  'fixtureOnly': true,
                  'upstreamDeliberatelyPending': true,
                  'localAutosaveBeforeReply': true,
                  'saveLockCancelsRequest': true,
                  'lateReplyDiscarded': true,
                  'reopenedDraftAndEditPreserved': true,
                }),
              );
        }
      } finally {
        ai.complete();
        await tester.pumpWidget(const SizedBox());
        if (c.isUnlocked) await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}

class _FixturePicker extends FilePickerPlatform {
  _FixturePicker(this.path, this.size);
  final String path;
  final int size;
  @override
  Future<PlatformFile?> pickFile({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    DarwinOptions darwinOptions = const DarwinOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async => _FixtureFile(path);
}

class _NoSpeechModel implements SpeechProvider {
  @override
  Future<bool> isModelInstalled() async => false;
  @override
  Future<void> downloadModel(SpeechDownloadProgress progress) async {}
  @override
  Future<void> installArchive(String path) async {}
  @override
  Future<void> removeModel() async {}
  @override
  Future<void> cancelDownload() async {}
  @override
  Future<String> transcribe(Uint8List wav) async =>
      throw StateError('fixture local model absent');
}

final class _FixtureFile extends PlatformFile {
  _FixtureFile(String path) : xFile = XFile(path);
  @override
  final XFile xFile;
  @override
  String get name => 'fixture.wav';
  @override
  Uri get uri => Uri.file(xFile.path);
  @override
  int? lengthSync() => null;
  @override
  Future<int?> length() => xFile.length();
  @override
  Future<Uint8List> readAsBytes() => xFile.readAsBytes();
  @override
  Stream<Uint8List> readAsByteStream() => xFile.openRead();
}

Future<void> _mediaConversionTest(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  final root = await Directory.systemTemp.createTemp('liverelay-media-ui-');
  final source = await File('${root.path}/fixture.wav').writeAsBytes(wave());
  final m4a = File('${root.path}/fixture.m4a');
  expect(
    (await Process.run('ffmpeg', [
      '-v',
      'error',
      '-i',
      source.path,
      '-c:a',
      'aac',
      m4a.path,
    ])).exitCode,
    0,
  );
  final originalBytes = await m4a.readAsBytes();
  final provider = RecordingConversationAi();
  final local = FixtureWindowSpeech();
  final speech = createSpeechService(
    local,
    supported: true,
    remoteProvider: local,
  );
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    provider,
    TestAiSettings()
      ..configured = true
      ..audio = true,
    null,
    null,
    null,
    speech,
  );
  final q = AgentConversation(c);
  final shot = GlobalKey();
  Future<void> wait(bool Function() ready) async {
    for (var i = 0; i < 120 && !ready(); i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(ready(), true);
  }

  try {
    await c.initialize();
    await c.setupVault(
      password: 'fixture-media-password',
      usesChinesePassphrase: false,
    );
    await q.addFilePaths([m4a.path]);
    final attachment = q.attachments.single;
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: shot,
          child: Scaffold(
            body: AnimatedBuilder(
              animation: q,
              builder: (context, _) => AttachmentStrip(conversation: q),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(ValueKey('attachment-preview-${attachment.id}')),
    );
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('准备完整WAV音轨'));
    await wait(
      () =>
          attachment.normalizedAudio != null &&
          find.text('准备完整WAV音轨').evaluate().isEmpty,
    );
    expect(attachment.bytes, originalBytes);
    final oldTurn = q.prepare('音轨', []);
    final wire = attachment.wireParts(
      AiProtocol.chatCompletions,
      images: false,
      files: false,
      audio: true,
    );
    expect(wire.single['type'], 'input_audio');
    await tester.tap(
      find.byKey(ValueKey('attachment-preview-${attachment.id}')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('转写并核对音轨'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('转写当前附件音轨'));
    final field = find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.labelText == '检查或修改识别文字',
    );
    await wait(
      () =>
          field.evaluate().isNotEmpty &&
          tester.widget<TextField>(field).controller!.text == '虚构转写',
    );
    await tester.enterText(field, '本人核对M4A转写');
    await tester.ensureVisible(find.text('使用核对文字发送此附件'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('使用核对文字发送此附件'));
    await wait(
      () =>
          attachment.transcript == '本人核对M4A转写' &&
          find.text('转写并核对音轨').evaluate().isEmpty,
    );
    expect(attachment.bytes, originalBytes);
    expect(c.blobs, isEmpty);
    expect(await q.send(oldTurn), false);
    expect(provider.requests, isEmpty);
    final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
    if (evidence != null) {
      final image =
          await (shot.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage();
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('$evidence/native-media-conversion.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }
    expect(await q.send(q.prepare('核对音频', [])), true);
    expect(
      provider.requests.single.inputContent!.where(
        (p) => p['type'] == 'input_audio',
      ),
      isEmpty,
    );
    expect(
      jsonEncode(provider.requests.single.inputContent),
      contains('本人核对M4A转写'),
    );
    expect(await q.send(q.prepare('整理为草稿', [])), true);
    await q.accept(q.messages.last);
    final card = c.cards.single;
    final review = (await c.cardReviewSource(card.id))!;
    final retained = review.inputs.first.attachments.single;
    expect(retained.bytes, originalBytes);
    expect(retained.transcript, '本人核对M4A转写');
    expect(retained.normalizedAudio, isNotNull);
    retained.wipe();
    await q.flush();
    await tester.pumpWidget(const SizedBox());
    await c.lock();
    await c.unlockWithPassword('fixture-media-password');
    await q.load();
    final restored = (await c.cardReviewSource(card.id))!
        .inputs
        .first
        .attachments
        .single;
    expect(restored.bytes, originalBytes);
    expect(restored.transcript, '本人核对M4A转写');
    restored.wipe();
    if (evidence != null) {
      await File('$evidence/media-conversion-verification.json').writeAsString(
        jsonEncode({
          'fixtureOnly': true,
          'realFfmpegM4a': true,
          'fullWavPrepared': true,
          'reviewedTranscriptAdopted': true,
          'staleAuthorizationRejected': true,
          'originalM4aRetained': true,
          'noImplicitBlob': true,
          'confirmationEvidenceReopened': true,
          'microphoneHardwareTested': false,
          'upstreamAsrTested': false,
        }),
      );
    }
  } finally {
    await tester.pumpWidget(const SizedBox());
    q.dispose();
    await c.lock();
    c.dispose();
    await root.delete(recursive: true);
  }
}
