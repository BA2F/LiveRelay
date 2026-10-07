import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/presentation/workbench/detached_workbench.dart';
import 'package:live_relay/presentation/workbench/native_window_host.dart';
import 'package:live_relay/application/workbench/card_edit_sessions.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/application/workbench/window_conversation_bridge.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../test/support/verification_fakes.dart';
import '../test/support/pdf_fixture.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == '--liverelay-workbench') {
    WidgetsFlutterBinding.ensureInitialized();
    await runDetachedWorkbench(arguments);
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
                listenable: edits,
                builder: (context, _) =>
                    Text(edits.session(c.cards.single).title),
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
    for (var i = 0; i < 150; i++) {
      final value = await child.channel.invokeMethod<Map>('inspect');
      if (value != null && matches(value)) return value;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    throw StateError('独立确认来源未就绪');
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
  final host = NativeWindowHost(
    controller: c,
    edits: edits,
    conversation: q,
    onDock: (_) {},
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
