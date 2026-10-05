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
import 'package:live_relay/infrastructure/app_composition.dart';

import '../test/support/verification_fakes.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.firstOrNull == '--liverelay-workbench') {
    WidgetsFlutterBinding.ensureInitialized();
    await runDetachedWorkbench(arguments);
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
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
        onSend: () async {},
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
}
