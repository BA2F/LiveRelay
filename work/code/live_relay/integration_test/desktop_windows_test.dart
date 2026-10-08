import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:live_relay/infrastructure/desktop_owner_window.dart';
import 'package:live_relay/presentation/workbench/detached_workbench.dart';
import 'package:live_relay/presentation/workbench/native_window_host.dart';
import 'package:live_relay/application/workbench/card_edit_sessions.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/application/workbench/window_conversation_bridge.dart';
import 'package:live_relay/application/workbench/window_projection.dart';
import 'package:live_relay/application/workbench/extension_registry.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:live_relay/infrastructure/app_composition.dart';

import '../test/support/verification_fakes.dart';
import '../test/support/pdf_fixture.dart';
import '../test/workbench/remote_speech_test.dart' show wave;
import '../test/workbench/window_speech_bridge_test.dart'
    show FixtureWindowSpeech;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == '--liverelay-workbench') {
    WidgetsFlutterBinding.ensureInitialized();
    await runDetachedWorkbench(arguments);
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native detached speech shares recognition, optional original and editable backfill',
    _speechWindowTest,
  );
  testWidgets(
    'native detached extension catalog contributes, revokes and persists shared views',
    _extensionWindowTest,
  );
  testWidgets(
    'native detached agent owns consent and shares attachments, editable plans and encrypted reopen',
    _agentWindowTest,
  );
  testWidgets(
    'native detached review reads immutable evidence, navigates and revokes',
    _reviewWindowTest,
  );
  testWidgets(
    'native detached engine shares edits, saves geometry, redocks and revokes on lock',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-windows-native-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingConversationAi(),
        TestAiSettings(),
      );
      final q = AgentConversation(c);
      final edits = CardEditSessions(
        save: (id, draft) => c.updateCard(id, draft),
        canSave: () => c.isUnlocked && !c.isBusy,
      );
      final docked = <String>[];
      final host = NativeWindowHost(
        controller: c,
        edits: edits,
        conversation: q,
        onDock: docked.add,
        diagnostics: true,
      );
      c.addListener(() {
        if (c.isUnlocked) edits.synchronize(c.cards);
      });
      Future<Map> inspect(DetachedWorkbenchSession window) async {
        for (var i = 0; i < 150; i++) {
          try {
            final data = await window.channel.invokeMethod<Map>('inspect');
            if (data != null && data['view'] != null) return data;
          } on Object {
            /* child engine still starting */
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
        throw StateError('子窗口未启动');
      }

      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-window-password',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '双窗口草稿',
            content: '虚构资料',
            status: CardStatus.draft,
          ),
        );
        final card = c.cards.single;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListenableBuilder(
                listenable: Listenable.merge([c, edits]),
                builder: (context, _) => Text(
                  c.cards.isEmpty
                      ? '资料库已锁定'
                      : edits.session(c.cards.single).title,
                ),
              ),
            ),
          ),
        );
        final child = await host.open(
          'card/${card.id}',
          bounds: {'x': 30, 'y': 30, 'width': 680, 'height': 600},
        );
        expect(child.window.process.pid, isNot(pid));
        expect((await child.window.directory.stat()).mode & 0x1ff, 0x1c0);
        // After authentication ServerSocket.close removes the listening path;
        // only the already paired connection remains available.
        expect(
          await File('${child.window.directory.path}/view.sock').exists(),
          false,
        );
        expect(
          child.window.arguments,
          isNot(contains('fixture-window-password')),
        );
        var data = await inspect(child);
        expect(data['vaultOwner'], false);
        expect((data['cards'] as List).single['title'], '双窗口草稿');
        final monitors = await Process.run('xrandr', ['--listmonitors']);
        final screens = RegExp(r'(\d+)/\d+x(\d+)/\d+([+-]\d+)([+-]\d+)')
            .allMatches(monitors.stdout.toString())
            .toList();
        if (await nativeDesktopBackend() == 'x11' &&
            monitors.exitCode == 0 &&
            screens.length > 1) {
          final before = Map<String, dynamic>.from(data['bounds'] as Map);
          final beforeCenter = Offset(
            (before['x'] as num).toDouble() +
                (before['width'] as num).toDouble() / 2,
            (before['y'] as num).toDouble() +
                (before['height'] as num).toDouble() / 2,
          );
          final monitorBounds = [
            for (final screen in screens)
              Rect.fromLTWH(
                double.parse(screen.group(3)!),
                double.parse(screen.group(4)!),
                double.parse(screen.group(1)!),
                double.parse(screen.group(2)!),
              ),
          ];
          final initialMonitor = monitorBounds.indexWhere(
            (screen) => screen.contains(beforeCenter),
          );
          expect(initialMonitor, isNonNegative);
          final targetMonitor = monitorBounds.indexWhere(
            (screen) => !screen.contains(beforeCenter),
          );
          // A mirrored layout cannot prove movement to a different screen.
          expect(targetMonitor, isNonNegative);
          expect(targetMonitor, isNot(initialMonitor));
          final target = monitorBounds[targetMonitor];
          final x = target.left;
          final y = target.top;
          await child.channel.invokeMethod('diagnosticMove', {
            'x': x + 100,
            'y': y + 100,
            'width': 680.0,
            'height': 600.0,
          });
          await tester.pump(const Duration(milliseconds: 300));
          final placed = await inspect(child);
          expect((placed['bounds'] as Map)['x'], closeTo(x + 100, 4));
          expect((placed['bounds'] as Map)['y'], closeTo(y + 100, 4));
          final after = Map<String, dynamic>.from(placed['bounds'] as Map);
          final afterCenter = Offset(
            (after['x'] as num).toDouble() +
                (after['width'] as num).toDouble() / 2,
            (after['y'] as num).toDouble() +
                (after['height'] as num).toDouble() / 2,
          );
          expect(target.contains(afterCenter), isTrue);
          expect(monitorBounds[initialMonitor].contains(afterCenter), isFalse);
          final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
          if (evidence != null) {
            await File('$evidence/native-multimonitor-verification.json')
                .writeAsString(
                  jsonEncode({
                    'fixtureOnly': true,
                    'monitorCount': screens.length,
                    'backend': 'x11',
                    'initialMonitorIndex': initialMonitor,
                    'targetMonitorIndex': targetMonitor,
                    'movedBetweenDistinctMonitors': true,
                    'initialBounds': before,
                    'targetMonitorBounds': {
                      'x': target.left,
                      'y': target.top,
                      'width': target.width,
                      'height': target.height,
                    },
                    'nativeProcess': child.window.process.pid,
                    'bounds': placed['bounds'],
                    'manualMouseDragTested': false,
                  }),
                );
          }
          await child.channel.invokeMethod('diagnosticMove', {
            'x': 30.0,
            'y': 30.0,
            'width': 680.0,
            'height': 600.0,
          });
          await tester.pump(const Duration(milliseconds: 100));
        }

        await child.channel.invokeMethod('diagnosticCommand', {
          'method': 'edit',
          'arguments': {'id': card.id, 'field': 'title', 'text': '子窗口输入同步'},
        });
        await tester.pump(const Duration(milliseconds: 200));
        expect(edits.session(card).title, '子窗口输入同步');
        expect(find.text('子窗口输入同步'), findsOneWidget);
        expect(c.cards.single.status, CardStatus.draft);
        await edits.flush();
        expect(c.cards.single.title, '子窗口输入同步');
        edits.edit(edits.session(c.cards.single), content: '父窗口修改回传');
        await tester.pump(const Duration(milliseconds: 300));
        data = await inspect(child);
        expect((data['cards'] as List).single['content'], '父窗口修改回传');
        await child.channel.invokeMethod('diagnosticMove', {
          'x': 70.0,
          'y': 80.0,
          'width': 720.0,
          'height': 610.0,
        });
        await tester.pump(const Duration(milliseconds: 800));
        await host.flushChildren();
        final saved = jsonDecode((await c.readWorkbenchWindows())!) as Map;
        expect(saved['windows'].single['view'], 'card/${card.id}');
        expect(saved['windows'].single['bounds']['width'], 720.0);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final png = await child.channel.invokeMethod<Uint8List>('capture');
          await File('$evidence/native-window.png').writeAsBytes(png!);
          await File('$evidence/window-verification.json').writeAsString(
            jsonEncode({
              'differentEngines': true,
              'vaultOwnerInChild': false,
              'geometry': saved['windows'].single['bounds'],
              'fixtureOnly': true,
            }),
          );
        }
        q.messages.add(ConversationMessage('user', 'fixture plan source'));
        final planned = ConversationMessage(
          'assistant',
          'fixture planned reply',
          suggestions: [
            const AiCardSuggestion(
              title: 'must review in main',
              content: 'fixture',
              kind: CardKind.note,
              isInference: false,
            ),
          ],
          actions: [
            ReviewActions(
              referenceIds: [card.id],
              deceased: VisibilityLevel.full,
            ),
          ],
        );
        q.messages.add(planned);
        await q.retrySave();
        await child.channel.invokeMethod('diagnosticCommand', {
          'method': 'accept',
          'arguments': {'reviewId': planned.reviewId},
        });
        expect(planned.accepted, false);
        expect(c.cards.length, 1);
        await child.channel.invokeMethod('diagnosticClose');
        for (var i = 0; i < 100 && host.sessions.isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(host.sessions, isEmpty);
        expect(docked, ['card/${card.id}']);
        expect(c.isUnlocked, true);
        expect(
          (jsonDecode((await c.readWorkbenchWindows())!) as Map)['windows'],
          isEmpty,
        );
        final second = await host.open('cards');
        await inspect(second);
        await c.lock();
        for (var i = 0; i < 100 && host.sessions.isNotEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(host.sessions, isEmpty);
        expect(find.text('资料库已锁定'), findsOneWidget);
        await second.window.stop();
        expect(second.window.exited, true);
        await expectLater(
          second.channel.invokeMethod('snapshot'),
          throwsA(anything),
        );
        await c.unlockWithPassword('fixture-window-password');
        expect(c.cards.single.content, '父窗口修改回传');
        await host.restore();
        expect(host.sessions.single.view, 'cards');
        await inspect(host.sessions.single);
        await host.shutdown();
        expect(
          (jsonDecode((await c.readWorkbenchWindows())!) as Map)['windows'],
          isEmpty,
        );
      } finally {
        await host.shutdown(preserve: true);
        host.dispose();
        await tester.pumpWidget(const SizedBox());
        q.dispose();
        edits.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native detached source media plays, seeks and removes caches on revocation',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-child-media-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final q = AgentConversation(c);
      final edits = CardEditSessions(
        save: (id, draft) => c.updateCard(id, draft),
        canSave: () => c.isUnlocked && !c.isBusy,
      );
      final host = NativeWindowHost(
        controller: c,
        edits: edits,
        conversation: q,
        onDock: (_) {},
        diagnostics: true,
      );
      final caches = <File>[];
      Future<Map> inspect(
        DetachedWorkbenchSession child,
        bool Function(Map) ready,
      ) async {
        for (var i = 0; i < 150; i++) {
          try {
            final value = await child.channel.invokeMethod<Map>('inspect');
            if (value != null && ready(value)) return value;
          } on Object {
            /* independent child still starting */
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('独立窗口媒体未就绪');
      }

      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-child-media',
          usesChinesePassphrase: false,
        );
        for (final video in [false, true]) {
          final file = File('${root.path}/fixture.${video ? "mp4" : "wav"}');
          final result = await Process.run('ffmpeg', [
            '-hide_banner',
            '-loglevel',
            'error',
            '-f',
            'lavfi',
            '-i',
            video ? 'color=c=blue:s=160x90:r=24' : 'anullsrc=r=16000:cl=mono',
            '-t',
            '4',
            if (video) ...[
              '-c:v',
              'libx264',
              '-pix_fmt',
              'yuv420p',
            ] else ...[
              '-c:a',
              'pcm_s16le',
            ],
            file.path,
          ]);
          expect(result.exitCode, 0);
          await c.importOriginal(
            bytes: await file.readAsBytes(),
            originalName: file.uri.pathSegments.last,
            mimeType: video ? 'video/mp4' : 'audio/wav',
            mediaKind: video ? BlobMediaKind.video : BlobMediaKind.audio,
          );
        }
        final windows = <DetachedWorkbenchSession>[];
        for (final blob in c.blobs) {
          final child = await host.open('source/${blob.id}');
          windows.add(child);
          final before = await inspect(
            child,
            (v) => (v['media'] as Map)['ready'] == true,
          );
          expect(before['vaultOwner'], false);
          expect((before['media'] as Map)['playing'], false);
          expect(
            (before['media'] as Map)['duration'],
            greaterThanOrEqualTo(3900),
          );
          caches.add(File((before['media'] as Map)['cacheFile'] as String));
          expect(await caches.last.exists(), true);
          await child.channel.invokeMethod('diagnosticMedia', {'play': true});
          final playing = await inspect(
            child,
            (v) =>
                (v['media'] as Map)['playing'] == true &&
                (v['media'] as Map)['position'] >= 100,
          );
          expect(
            (playing['media'] as Map)['position'],
            greaterThanOrEqualTo(100),
          );
          await child.channel.invokeMethod('diagnosticMedia', {'play': false});
          await inspect(child, (v) => (v['media'] as Map)['playing'] == false);
          await child.channel.invokeMethod('diagnosticMedia', {
            'milliseconds': 1000,
          });
          await inspect(child, (v) => (v['media'] as Map)['position'] >= 900);
          final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
          if (evidence != null && blob.mediaKind == BlobMediaKind.video) {
            final bytes = await child.channel.invokeMethod<Uint8List>(
              'capture',
            );
            await File('$evidence/native-child-media.png').writeAsBytes(bytes!);
          }
        }
        final first = windows.first;
        final wrong = c.blobs.firstWhere((b) => 'source/${b.id}' != first.view);
        await first.channel.invokeMethod('diagnosticCommand', {
          'method': 'readSource',
          'arguments': {'id': wrong.id},
        });
        await inspect(first, (v) => v['error'] != null);
        await c.lock();
        for (final window in windows) {
          await window.window.process.exitCode.timeout(
            const Duration(seconds: 10),
          );
        }
        for (final file in caches) {
          expect(await file.exists(), false);
        }
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          await File('$evidence/child-media-verification.json').writeAsString(
            jsonEncode({
              'fixture': true,
              'independentProcesses': true,
              'vaultOwnerInChild': false,
              'nativeDecode': ['wav', 'mp4'],
              'defaultPaused': true,
              'playPauseSeek': true,
              'outOfViewReadRejected': true,
              'lockRevokesProcessesAndRemovesCaches': true,
            }),
          );
        }
      } finally {
        await host.shutdown(preserve: true);
        host.dispose();
        q.dispose();
        edits.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native detached PDF renders in a scoped child and exits on lock',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-child-pdf-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final q = AgentConversation(c);
      final edits = CardEditSessions(
        save: (id, draft) => c.updateCard(id, draft),
        canSave: () => c.isUnlocked && !c.isBusy,
      );
      final host = NativeWindowHost(
        controller: c,
        edits: edits,
        conversation: q,
        onDock: (_) {},
        diagnostics: true,
      );
      Future<Map> ready(DetachedWorkbenchSession child, int page) async {
        for (var i = 0; i < 150; i++) {
          try {
            final value = await child.channel.invokeMethod<Map>('inspect');
            if (value != null &&
                (value['pdf'] as Map)['ready'] == true &&
                (value['pdf'] as Map)['page'] == page) {
              return value;
            }
          } on Object {
            /* child still starting */
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('独立窗口PDF未就绪');
      }

      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-child-pdf',
          usesChinesePassphrase: false,
        );
        await c.importOriginal(
          bytes: syntheticPdf(),
          originalName: 'child-fixture.pdf',
          mimeType: 'application/octet-stream', // Earlier desktop imports.
          mediaKind: BlobMediaKind.document,
        );
        final child = await host.open('source/${c.blobs.single.id}');
        final before = await ready(child, 0);
        expect(child.window.process.pid, isNot(pid));
        expect(before['vaultOwner'], false);
        expect((before['pdf'] as Map)['pages'], 2);
        await child.channel.invokeMethod('diagnosticPdfPage', 1);
        await ready(child, 1);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final png = await child.channel.invokeMethod<Uint8List>('capture');
          await File('$evidence/native-child-pdf.png').writeAsBytes(png!);
        }
        await c.lock();
        expect(
          await child.window.process.exitCode.timeout(
            const Duration(seconds: 10),
          ),
          0,
        );
        await expectLater(
          child.channel.invokeMethod('snapshot'),
          throwsA(anything),
        );
        if (evidence != null) {
          await File('$evidence/child-pdf-verification.json').writeAsString(
            jsonEncode({
              'fixtureOnly': true,
              'independentProcess': true,
              'vaultOwnerInChild': false,
              'nativePdfiumPages': 2,
              'turnPage': true,
              'lockRevokesProcess': true,
            }),
          );
        }
      } finally {
        await host.shutdown(preserve: true);
        host.dispose();
        q.dispose();
        edits.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> _reviewWindowTest(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('liverelay-child-review-');
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    RecordingConversationAi(),
    TestAiSettings(),
  );
  final q = AgentConversation(c);
  final edits = CardEditSessions(
    save: (id, draft) => c.updateCard(id, draft),
    canSave: () => c.isUnlocked && !c.isBusy,
  );
  final docked = <String>[];
  final host = NativeWindowHost(
    controller: c,
    edits: edits,
    conversation: q,
    onDock: docked.add,
    diagnostics: true,
  );
  Future<Map> ready(
    DetachedWorkbenchSession child,
    bool Function(Map) matches,
  ) async {
    Map? last;
    for (var i = 0; i < 150; i++) {
      final value = await child.channel.invokeMethod<Map>('inspect');
      last = value;
      if (value != null && matches(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError(
      '独立确认来源未就绪：${{'view': last?['view'], 'review': last?['review'], 'error': last?['error']}}',
    );
  }

  try {
    await c.initialize();
    await c.setupVault(
      password: 'fixture-child-review',
      usesChinesePassphrase: false,
    );
    await c.createCard(const CardDraft(title: '所选资料', content: '确认时旧正文'));
    final selected = c.cards.single;
    q.attachCard(selected);
    final selection = q.attachments.removeLast();
    final pdf = ConversationAttachment.read(
      'review-fixture.pdf',
      Uint8List.fromList([...syntheticPdf(), ...List.filled(300000, 32)]),
    );
    q.messages.add(
      ConversationMessage('user', '虚构完整确认输入', attachments: [selection, pdf]),
    );
    final message = ConversationMessage(
      'assistant',
      '保留的完整答复',
      providerLabel: 'fixture review service',
      suggestions: [
        const AiCardSuggestion(
          title: '确认结果',
          content: '已核对的总结',
          kind: CardKind.note,
          isInference: false,
        ),
      ],
      actions: [
        ReviewActions(
          referenceIds: [selected.id],
          deceased: VisibilityLevel.summary,
        ),
      ],
    );
    q.messages.add(message);
    await q.accept(message);
    expect(q.error, isNull);
    final card = c.cards.singleWhere((c) => c.title == '确认结果');
    await q.newConversation();
    await c.updateCard(
      selected.id,
      const CardDraft(title: '所选资料', content: '后来修改正文'),
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('主工作台'))),
    );
    final child = await host.open('review/${card.id}');
    final loaded = await ready(
      child,
      (v) => (v['review'] as Map)['id'] == message.reviewId,
    );
    expect(child.window.process.pid, isNot(pid));
    expect(loaded['vaultOwner'], false);
    expect((loaded['review'] as Map)['inputs'], 1);
    expect((loaded['review'] as Map)['attachments'], 2);
    final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
    if (evidence != null) {
      final png = await child.channel.invokeMethod<Uint8List>('capture');
      await File('$evidence/native-child-review.png').writeAsBytes(png!);
    }
    await child.channel.invokeMethod('diagnosticCommand', {
      'method': 'readReview',
      'arguments': {'id': selected.id, 'offset': 0},
    });
    await ready(child, (v) => v['error'] != null);
    for (var visit = 0; visit < 5; visit++) {
      await child.channel.invokeMethod('diagnosticCommand', {
        'method': 'navigate',
        'arguments': {'view': 'card/${selected.id}'},
      });
      await ready(child, (v) => v['view'] == 'card/${selected.id}');
      await child.channel.invokeMethod('diagnosticCommand', {
        'method': 'navigate',
        'arguments': {'view': 'review/${card.id}'},
      });
      await ready(child, (v) => (v['review'] as Map)['id'] == message.reviewId);
    }
    await c.lock();
    expect(
      await child.window.process.exitCode.timeout(const Duration(seconds: 10)),
      0,
    );
    await c.unlockWithPassword('fixture-child-review');
    final stored = (await c.cardReviewSource(card.id))!;
    expect(stored.inputs.single.attachments.first.text, '所选资料\n确认时旧正文');
    expect(
      stored.inputs.single.attachments.last.bytes.length,
      greaterThan(300000),
    );
    expect(stored.actions.single.referenceIds, [selected.id]);
    stored.wipe();
    await host.restore();
    final restored = host.sessions.single;
    await ready(
      restored,
      (v) => (v['review'] as Map)['id'] == message.reviewId,
    );
    await restored.channel.invokeMethod('diagnosticClose');
    for (var i = 0; i < 100 && host.sessions.isNotEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(docked, ['review/${card.id}']);
    if (evidence != null) {
      await File('$evidence/child-review-verification.json').writeAsString(
        jsonEncode({
          'fixtureOnly': true,
          'independentProcess': true,
          'vaultOwnerInChild': false,
          'immutableInputsAndAttachments': true,
          'scopedReadRejected': true,
          'navigateReload': true,
          'consecutiveRoundTrips': 5,
          'lockRevokesProcess': true,
          'unlockRestoresView': true,
          'closeRedocks': true,
        }),
      );
    }
  } finally {
    await host.shutdown(preserve: true);
    host.dispose();
    await tester.pumpWidget(const SizedBox());
    q.dispose();
    edits.dispose();
    if (c.isUnlocked) await c.lock();
    c.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _agentWindowTest(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp('liverelay-child-agent-');
  final ai = RecordingConversationAi();
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    ai,
    TestAiSettings()..configured = true,
  );
  final q = AgentConversation(c);
  final edits = CardEditSessions(
    save: (id, draft) => c.updateCard(id, draft),
    canSave: () => c.isUnlocked && !c.isBusy,
  );
  final ownerTools = <String>[];
  final ownerResults = <Map>[];
  final backend = await nativeDesktopBackend();
  var ownerActivations = 0;
  final host = NativeWindowHost(
    controller: c,
    edits: edits,
    conversation: q,
    onDock: ownerTools.add,
    activateMain: (token) async {
      ownerActivations++;
      return await activateOwnerWindow(activationToken: token);
    },
    diagnostics: true,
  );
  Future<Map> waitAgent(
    DetachedWorkbenchSession child,
    bool Function(Map) ready,
  ) async {
    for (var i = 0; i < 200; i++) {
      try {
        final data = await child.channel.invokeMethod<Map>('inspect');
        final agent = data?['agent'];
        if (agent is Map && ready(agent)) return agent;
      } on Object {
        /* starting or invalidation */
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw StateError('独立助手未达到预期状态');
  }

  try {
    await c.initialize();
    await c.setupVault(
      password: 'fixture-agent-window-password',
      usesChinesePassphrase: false,
    );
    await c.createCard(const CardDraft(title: '引用目标', content: '虚构目标'));
    final target = c.cards.single;
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('fixture agent window'))),
    );
    final child = await host.open(
      'agent',
      bounds: {'x': 30, 'y': 30, 'width': 920, 'height': 840},
    );
    Future<dynamic> ask(String method, [Map args = const {}]) =>
        child.channel.invokeMethod('diagnosticRequest', {
          'method': method,
          'arguments': args,
        });
    await waitAgent(child, (a) => a['draft'] != null);
    for (final tool in ['settings', 'passwords', 'handoff', 'recycle']) {
      final result = await child.channel.invokeMethod<Map>(
        'diagnosticOpenMain',
        tool,
      );
      expect(result?['opened'], true);
      ownerResults.add(result!);
      for (
        var tick = 0;
        tick < 30 && !await windowManager.isFocused();
        tick++
      ) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (backend == 'x11') {
        expect(await windowManager.isFocused(), true);
        expect(result['focused'], true);
      } else if (result['focused'] == false) {
        final inspected = await child.channel.invokeMethod<Map>('inspect');
        expect(
          inspected?['ownerWindowHint'],
          contains(ownerWorkbenchTools[tool]!),
        );
        expect(inspected?['ownerWindowHint'], contains('主窗口'));
      }
      expect(child.view, 'agent');
    }
    expect(ownerTools, ['settings', 'passwords', 'handoff', 'recycle']);
    expect(ownerActivations, 4);
    for (final token in [true, '', 'x' * 1025, 'bad\u0000token']) {
      await expectLater(
        ask('openMain', {'view': 'settings', 'activationToken': token}),
        throwsA(anything),
      );
    }
    expect(ownerTools, ['settings', 'passwords', 'handoff', 'recycle']);
    expect(ownerActivations, 4);
    await expectLater(
      ask('openMain', {'view': 'vault/full'}),
      throwsA(anything),
    );
    expect(ownerActivations, 4);
    await ask('draft', {'text': '第一轮虚构输入\nfixture private line'});
    await ask('mark', {'line': 1, 'kind': 'secret'});
    var consent = await ask('prepareSend') as Map;
    expect(consent['text'], contains('[[TURN1_SECRET_01]]'));
    expect(consent['text'], isNot(contains('fixture private line')));
    q.updateDraft('changed elsewhere');
    await expectLater(
      ask('send', {'ticket': consent['ticket']}),
      throwsA(anything),
    );
    expect(ai.requests, isEmpty);
    await ask('draft', {'text': '第一轮虚构输入'});
    consent = await ask('prepareSend') as Map;
    await ask('send', {'ticket': consent['ticket']});
    await waitAgent(
      child,
      (a) => a['working'] == false && (a['messages'] as List).length == 2,
    );
    expect(ai.requests, hasLength(1));
    final file = File('${root.path}/fixture.txt');
    await file.writeAsString('独立附件虚构内容');
    await ask('addFiles', {
      'paths': [file.path],
    });
    await ask('attachCard', {'id': target.id});
    final attached = await waitAgent(
      child,
      (a) => (a['attachments'] as List).length == 2,
    );
    expect(c.blobs, isEmpty);
    final attachmentId = (attached['attachments'] as List).first['id'];
    final bytes = await ask('readAttachment', {'id': attachmentId}) as Map;
    expect(utf8.decode(bytes['bytes'] as Uint8List), '独立附件虚构内容');
    (bytes['bytes'] as Uint8List).fillRange(
      0,
      (bytes['bytes'] as Uint8List).length,
      0,
    );
    await expectLater(
      ask('readAttachment', {'id': 'unselected'}),
      throwsA(anything),
    );
    await ask('saveAttachment', {'id': attachmentId});
    expect(c.blobs, hasLength(1));
    await ask('draft', {'text': '请继续整理'});
    consent = await ask('prepareSend') as Map;
    expect(consent['targets'], hasLength(1));
    await ask('send', {'ticket': consent['ticket']});
    await waitAgent(
      child,
      (a) => a['working'] == false && (a['messages'] as List).length == 4,
    );
    final message = q.messages.last;
    await ask('editSuggestion', {
      'reviewId': message.reviewId,
      'index': 0,
      'suggestion': {
        'title': '独立窗口本人修改',
        'tags': ['本人核对'],
        'kind': 'location',
        'inference': true,
      },
    });
    await ask('editActions', {
      'reviewId': message.reviewId,
      'index': 0,
      'plan': ReviewActions(
        referenceIds: [target.id],
        deceased: VisibilityLevel.summary,
      ).toJson(),
    });
    final rendered = await waitAgent(
      child,
      (a) =>
          ((a['messages'] as List).last['actions'] as List)
              .single['deceased'] ==
          'summary',
    );
    final shown = (rendered['messages'] as List).last['stamp'];
    expect(shown, windowReviewStamp(message));
    final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
    if (evidence != null) {
      final png = await child.channel.invokeMethod<Uint8List>('capture');
      await File('$evidence/native-child-agent.png').writeAsBytes(png!);
    }
    q.editSuggestion(message, 0, content: '主工作台再次更新');
    await expectLater(
      ask('accept', {'reviewId': message.reviewId, 'stamp': shown}),
      throwsA(anything),
    );
    expect(message.accepted, false);
    await ask('accept', {
      'reviewId': message.reviewId,
      'stamp': windowReviewStamp(message),
    });
    expect(message.accepted, true);
    final saved = c.cards.singleWhere((item) => item.title == '独立窗口本人修改');
    expect(saved.title, '独立窗口本人修改');
    expect(saved.kind, CardKind.location);
    expect(c.cardReferences.single.to, target.id);
    final source = await c.cardReviewSource(saved.id);
    expect(source!.inputs.last.attachments, hasLength(2));
    expect(source.actions.single.deceased, VisibilityLevel.summary);
    source.wipe();
    await ask('flush');
    await c.lock();
    expect(
      await child.window.process.exitCode.timeout(const Duration(seconds: 5)),
      0,
    );
    await c.unlockWithPassword('fixture-agent-window-password');
    await q.load();
    expect(q.messages.last.accepted, true);
    await host.restore();
    final restored = host.sessions.single;
    await waitAgent(
      restored,
      (a) => (a['messages'] as List).last['accepted'] == true,
    );
    expect(
      (await restored.channel.invokeMethod<Map>('inspect'))!['vaultOwner'],
      false,
    );
    if (evidence != null) {
      await File('$evidence/child-agent-verification.json').writeAsString(
        jsonEncode({
          'fixtureOnly': true,
          'ownerTools': ownerTools,
          'backend': backend,
          'ownerWindowFocused': ownerResults.every((r) => r['focused'] == true),
          'ownerToolResults': ownerResults,
          'fallbackShownWhenFocusDenied': true,
          'invalidActivationTokensRejected': true,
          'invalidOwnerToolRejected': true,
          'nativeIndependentProcess': true,
          'vaultOwnerInChild': false,
          'consentRedacted': true,
          'staleConsentRejected': true,
          'attachmentsScoped': true,
          'separateStoreOriginal': true,
          'ownerSuggestionFields': true,
          'fullOwnerPlan': true,
          'stalePlanRejected': true,
          'sourceAttachmentsPreserved': true,
          'lockRevokesProcess': true,
          'encryptedReopen': true,
        }),
      );
    }
  } finally {
    await host.shutdown(preserve: true);
    host.dispose();
    await tester.pumpWidget(const SizedBox());
    q.dispose();
    edits.dispose();
    if (c.isUnlocked) await c.lock();
    c.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _extensionWindowTest(WidgetTester tester) async {
  final root = await Directory.systemTemp.createTemp(
    'liverelay-child-extensions-',
  );
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    RecordingAi(),
    TestAiSettings(),
  );
  final q = AgentConversation(c);
  final registry = ExtensionRegistry(
    read: c.readWorkbenchExtensions,
    write: c.writeWorkbenchExtensions,
  );
  final edits = CardEditSessions(
    save: (id, draft) => c.updateCard(id, draft),
    canSave: () => c.isUnlocked && !c.isBusy,
  );
  final host = NativeWindowHost(
    controller: c,
    edits: edits,
    conversation: q,
    extensions: registry,
    onDock: (_) {},
    diagnostics: true,
  );
  Future<Map> wait(
    DetachedWorkbenchSession child,
    bool Function(Map) ready,
  ) async {
    for (var i = 0; i < 150; i++) {
      try {
        final data = await child.channel.invokeMethod<Map>('inspect');
        if (data != null && ready(data)) return data;
      } on Object {
        /* startup or invalidation */
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw StateError('扩展子窗口未达到预期状态');
  }

  try {
    await c.initialize();
    await c.setupVault(
      password: 'fixture-extensions-password',
      usesChinesePassphrase: false,
    );
    await c.createCard(
      const CardDraft(
        title: '独立扩展待确认',
        content: '虚构摘要',
        status: CardStatus.draft,
      ),
    );
    final draft = c.cards.single;
    await c.createCard(const CardDraft(title: '已确认应排除', content: '虚构摘要'));
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('fixture extensions'))),
    );
    final catalog = await host.open('extensions');
    Future<dynamic> ask(
      DetachedWorkbenchSession child,
      String method, [
      Map args = const {},
    ]) => child.channel.invokeMethod('diagnosticRequest', {
      'method': method,
      'arguments': args,
    });
    await wait(catalog, (data) => data['extensions'] is List);
    final raw = jsonDecode(
      await rootBundle.loadString('assets/extensions/draft-review.lrext.json'),
    ) as Map;
    await ask(catalog, 'installExtension', {'manifest': raw});
    await wait(catalog, (data) => (data['extensions'] as List).length == 1);
    final view = registry.commands.single.view;
    final contribution = await host.open(view);
    final projected = await wait(
      contribution,
      (data) => (data['contributed'] as List? ?? []).length == 1,
    );
    expect((projected['contributed'] as List).single['id'], draft.id);
    expect(projected['vaultOwner'], false);
    await expectLater(
      ask(contribution, 'removeExtension', {'id': 'liverelay.draft-review'}),
      throwsA(anything),
    );
    await ask(catalog, 'extensionSetting', {
      'id': 'liverelay.draft-review',
      'key': 'only-sourced',
      'value': true,
    });
    await wait(
      contribution,
      (data) => (data['contributed'] as List? ?? []).isEmpty,
    );
    await c.importOriginal(
      bytes: Uint8List.fromList(utf8.encode('虚构来源')),
      originalName: 'fixture.txt',
      mimeType: 'text/plain',
      mediaKind: BlobMediaKind.document,
    );
    await c.setCardOriginals(draft.id, [c.blobs.single.id]);
    await wait(
      contribution,
      (data) => (data['contributed'] as List? ?? []).any(
        (item) => item['id'] == draft.id,
      ),
    );
    final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
    if (evidence != null) {
      final png = await catalog.channel.invokeMethod<Uint8List>('capture');
      await File('$evidence/native-child-extensions.png').writeAsBytes(png!);
    }
    await ask(catalog, 'enableExtension', {
      'id': 'liverelay.draft-review',
      'enabled': false,
    });
    expect(registry.commands, isEmpty);
    await wait(contribution, (data) => data['view'] == 'extensions');
    await expectLater(
      ask(catalog, 'navigate', {'view': view}),
      throwsA(anything),
    );
    await ask(catalog, 'enableExtension', {
      'id': 'liverelay.draft-review',
      'enabled': true,
    });
    await c.lock();
    expect(
      await catalog.window.process.exitCode.timeout(const Duration(seconds: 5)),
      0,
    );
    expect(
      await contribution.window.process.exitCode.timeout(
        const Duration(seconds: 5),
      ),
      0,
    );
    await c.unlockWithPassword('fixture-extensions-password');
    await registry.load();
    expect(registry.installed.values.single.setting('only-sourced'), true);
    await host.restore();
    final restored = host.sessions.first;
    await wait(
      restored,
      (data) => (data['extensions'] as List? ?? []).length == 1,
    );
    await ask(restored, 'removeExtension', {'id': 'liverelay.draft-review'});
    expect(registry.installed, isEmpty);
    expect(registry.commands, isEmpty);
    expect(c.cards.any((item) => item.id == draft.id), true);
    if (evidence != null) {
      await File('$evidence/child-extensions-verification.json').writeAsString(
        jsonEncode({
          'fixtureOnly': true,
          'sharedNativeCatalog': true,
          'contributedView': true,
          'sourceSettingAppliedAcrossWindows': true,
          'managementScopeEnforced': true,
          'disabledCommandsRevoked': true,
          'disabledViewRedirected': true,
          'encryptedReopen': true,
          'removeKeepsCards': true,
        }),
      );
    }
  } finally {
    await host.shutdown(preserve: true);
    host.dispose();
    await tester.pumpWidget(const SizedBox());
    q.dispose();
    edits.dispose();
    registry.dispose();
    if (c.isUnlocked) await c.lock();
    c.dispose();
    await root.delete(recursive: true);
  }
}

Future<void> _speechWindowTest(WidgetTester tester) async {
  FlutterSecureStorage.setMockInitialValues({});
  final root = await Directory.systemTemp.createTemp(
    'liverelay-child-speech-native-',
  );
  final file = await File('${root.path}/fixture.wav').writeAsBytes(wave());
  final m4a = File('${root.path}/fixture.m4a');
  expect(
    (await Process.run('ffmpeg', [
      '-v',
      'error',
      '-i',
      file.path,
      '-c:a',
      'aac',
      m4a.path,
    ])).exitCode,
    0,
  );
  final provider = FixtureWindowSpeech();
  final speech = createSpeechService(
    provider,
    supported: true,
    remoteProvider: provider,
  );
  final ai = RecordingConversationAi();
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    ai,
    TestAiSettings(),
    null,
    null,
    null,
    speech,
  );
  final q = AgentConversation(c);
  final edits = CardEditSessions(
    save: (id, draft) => c.updateCard(id, draft),
    canSave: () => c.isUnlocked && !c.isBusy,
  );
  final host = NativeWindowHost(
    controller: c,
    edits: edits,
    conversation: q,
    onDock: (_) {},
    diagnostics: true,
  );
  Future<Map> wait(
    DetachedWorkbenchSession child,
    bool Function(Map) ready,
  ) async {
    for (var i = 0; i < 150; i++) {
      try {
        final d = await child.channel.invokeMethod<Map>('inspect');
        if (d != null && ready(d)) return d;
      } on Object {
        /* Engine startup/invalidation. */
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    throw StateError('语音子窗口未达到预期状态');
  }

  Future<dynamic> ask(
    DetachedWorkbenchSession child,
    String method, [
    Map args = const {},
  ]) => child.channel.invokeMethod('diagnosticRequest', {
    'method': method,
    'arguments': args,
  });
  try {
    await c.initialize();
    await c.setupVault(
      password: 'fixture-speech-password',
      usesChinesePassphrase: false,
    );
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: Text('fixture speech'))),
    );
    final child = await host.open('speech');
    final status = await wait(
      child,
      (d) => d['transcript'] == '' && d['speech']?['ready'] == true,
    );
    expect(status['vaultOwner'], false);
    expect(status['savesOriginal'], false);
    await child.channel.invokeMethod('diagnosticSpeech', {'path': file.path});
    await wait(child, (d) => d['transcript'] == '虚构转写');
    expect(c.blobs, isEmpty);
    expect(c.cards, isEmpty);
    q.updateDraft('原有输入');
    await child.channel.invokeMethod('diagnosticSpeech', {'backfill': true});
    await wait(child, (d) => d['view'] == 'agent');
    expect(q.draft, '原有输入\n虚构转写');
    expect(ai.requests, isEmpty);
    await ask(child, 'navigate', {'view': 'speech'});
    await wait(child, (d) => d['transcript'] == '');
    await child.channel.invokeMethod('diagnosticSpeech', {
      'path': m4a.path,
      'saveOriginal': true,
    });
    await wait(
      child,
      (d) => d['transcript'] == '虚构转写' && d['savesOriginal'] == true,
    );
    expect(c.blobs, hasLength(1));
    expect(await c.readOriginal(c.blobs.single.id), await m4a.readAsBytes());
    expect(c.blobs.single.mimeType, 'audio/mp4');
    final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
    if (evidence != null) {
      final bytes = await child.channel.invokeMethod<Uint8List>('capture');
      await File('$evidence/native-child-speech.png').writeAsBytes(bytes!);
    }
    await child.channel.invokeMethod('diagnosticSpeech', {'saveDraft': true});
    await wait(child, (d) => d['transcript'] == '');
    final draft = c.cards.singleWhere((card) => card.content == '虚构转写');
    expect(draft.status, CardStatus.draft);
    expect((await c.cardSources(draft.id)).first.blobId, c.blobs.single.id);
    await q.flush();
    await c.lock();
    await host.shutdown(preserve: true);
    expect(await child.window.process.exitCode, 0);
    await c.unlockWithPassword('fixture-speech-password');
    await q.load();
    expect(q.draft, '原有输入\n虚构转写');
    expect(c.cards.any((card) => card.content == '虚构转写'), true);
    await host.restore();
    expect(host.sessions.single.view, 'speech');
    await wait(host.sessions.single, (d) => d['transcript'] == '');
    if (evidence != null) {
      await File('$evidence/child-speech-verification.json').writeAsString(
        jsonEncode({
          'fixtureOnly': true,
          'sharedNativeSpeechPage': true,
          'defaultNoOriginal': true,
          'originalExplicitlySaved': true,
          'm4aConvertedForAsr': true,
          'originalM4aBytesPreserved': true,
          'backfillPreservesDraft': true,
          'noAutomaticAiSend': true,
          'associatedDraftSaved': true,
          'encryptedReopen': true,
          'lockRevokedChild': true,
          'microphoneHardwareTested': false,
          'remoteUpstreamTested': false,
        }),
      );
    }
  } finally {
    await host.shutdown();
    host.dispose();
    q.dispose();
    edits.dispose();
    await tester.pumpWidget(const SizedBox());
    await c.lock();
    c.dispose();
    await root.delete(recursive: true);
  }
}
