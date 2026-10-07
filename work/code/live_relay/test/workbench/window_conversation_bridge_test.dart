import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/application/workbench/window_conversation_bridge.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('detached consent hides tokens and keys; changed draft, marks, config, cancellation and replay cannot send', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-window-consent-',
    );
    final ai = RecordingConversationAi();
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    final q = AgentConversation(c);
    var active = true;
    final bridge = WindowConversationBridge(q, active: () => active);
    Future<dynamic> invoke(String method, [Map args = const {}]) =>
        bridge.invoke(MethodCall(method, args));
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-only-password',
        usesChinesePassphrase: false,
      );
      await invoke('draft', {'text': 'fixture secret\npublic'});
      await invoke('mark', {'line': 0, 'kind': 'secret'});
      var consent = await invoke('prepareSend') as Map;
      expect(consent['text'], '[[TURN1_SECRET_01]]\npublic');
      expect(jsonEncode(consent), isNot(contains('fixture secret')));
      expect(jsonEncode(consent), isNot(contains('test-key')));
      await invoke('draft', {'text': 'changed'});
      await expectLater(
        invoke('send', {'ticket': consent['ticket']}),
        throwsFormatException,
      );
      consent = await invoke('prepareSend') as Map;
      await invoke('mark', {'line': 0, 'kind': 'note'});
      await expectLater(
        invoke('send', {'ticket': consent['ticket']}),
        throwsFormatException,
      );
      consent = await invoke('prepareSend') as Map;
      await c.saveAiSettings(
        endpoint: c.aiSettings.endpoint,
        model: c.aiSettings.model,
      );
      await expectLater(
        invoke('send', {'ticket': consent['ticket']}),
        throwsFormatException,
      );
      consent = await invoke('prepareSend') as Map;
      await invoke('cancelSend');
      await expectLater(
        invoke('send', {'ticket': consent['ticket']}),
        throwsFormatException,
      );
      expect(ai.requests, isEmpty);
      consent = await invoke('prepareSend') as Map;
      await invoke('send', {'ticket': consent['ticket']});
      for (var i = 0; i < 100 && q.working; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ai.requests, hasLength(1));
      expect(ai.requests.single.redactedText, '[[TURN1_NOTE_01]]');
      await expectLater(
        invoke('send', {'ticket': consent['ticket']}),
        throwsFormatException,
      );
      active = false;
      await expectLater(
        invoke('prepareSend'),
        throwsA(isA<PlatformException>()),
      );
      expect(ai.requests, hasLength(1));
    } finally {
      bridge.clear();
      q.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });

  test('detached owner edits and full plans use the shown stamp, remain atomic and survive encrypted reopen', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-window-plan-',
    );
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      RecordingConversationAi(),
      TestAiSettings(),
    );
    final q = AgentConversation(c);
    final bridge = WindowConversationBridge(q, active: () => true);
    Future<dynamic> invoke(String method, [Map args = const {}]) =>
        bridge.invoke(MethodCall(method, args));
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-only-password',
        usesChinesePassphrase: false,
      );
      await c.createCard(const CardDraft(title: 'target', content: 'fixture'));
      final target = c.cards.single;
      q.messages.add(ConversationMessage('user', 'full fixture input'));
      final message = ConversationMessage(
        'assistant',
        'fixture reply',
        suggestions: [
          const AiCardSuggestion(
            title: 'old',
            content: 'model body',
            kind: CardKind.note,
            isInference: false,
          ),
        ],
      );
      q.messages.add(message);
      final stale = windowReviewStamp(message);
      await invoke('editSuggestion', {
        'reviewId': message.reviewId,
        'index': 0,
        'suggestion': {'title': 'owner title'},
      });
      await invoke('editSuggestion', {
        'reviewId': message.reviewId,
        'index': 0,
        'suggestion': {
          'tags': ['owner'],
          'inference': true,
          'kind': 'location',
        },
      });
      await invoke('editActions', {
        'reviewId': message.reviewId,
        'index': 0,
        'plan': ReviewActions(
          referenceIds: [target.id],
          deceased: VisibilityLevel.summary,
        ).toJson(),
      });
      await expectLater(
        invoke('accept', {'reviewId': message.reviewId, 'stamp': stale}),
        throwsFormatException,
      );
      expect(c.cards, hasLength(1));
      await invoke('accept', {
        'reviewId': message.reviewId,
        'stamp': windowReviewStamp(message),
      });
      expect(message.accepted, true);
      final saved = c.cards.singleWhere((card) => card.id != target.id);
      expect(saved.title, 'owner title');
      expect(saved.kind, CardKind.location);
      expect(saved.tags, contains('owner'));
      expect(c.cardReferences.single.to, target.id);
      final source = await c.cardReviewSource(saved.id);
      expect(source!.actions.single.deceased, VisibilityLevel.summary);
      source.wipe();
      await q.flush();
      await c.lock();
      await c.unlockWithPassword('fixture-only-password');
      await q.load();
      expect(q.messages.last.accepted, true);
      expect(q.messages.last.actions.single.referenceIds, [target.id]);
      expect(q.messages.last.suggestions.single.title, 'owner title');
    } finally {
      bridge.clear();
      q.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });

  test('detached attachments are metadata-only; bounded scoped reads own copies, selection is independent of storing', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-window-attachment-',
    );
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      RecordingConversationAi(),
      TestAiSettings(),
    );
    final q = AgentConversation(c);
    final bridge = WindowConversationBridge(q, active: () => true);
    Future<dynamic> invoke(String method, [Map args = const {}]) =>
        bridge.invoke(MethodCall(method, args));
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-only-password',
        usesChinesePassphrase: false,
      );
      final file = File('${root.path}/fixture.txt');
      await file.writeAsString('fixture bytes');
      await expectLater(
        invoke('addFiles', {
          'paths': ['relative.txt'],
        }),
        throwsFormatException,
      );
      await invoke('addFiles', {
        'paths': [file.path],
      });
      final a = q.attachments.single;
      expect(c.blobs, isEmpty);
      expect(
        jsonEncode(bridge.snapshot()['attachments']),
        isNot(contains('fixture bytes')),
      );
      final read = await invoke('readAttachment', {'id': a.id}) as Map;
      expect(utf8.decode(read['bytes'] as Uint8List), 'fixture bytes');
      (read['bytes'] as Uint8List).fillRange(0, a.bytes.length, 0);
      expect(a.text, 'fixture bytes');
      await expectLater(
        invoke('readAttachment', {'id': 'other'}),
        throwsFormatException,
      );
      await invoke('saveAttachment', {'id': a.id});
      expect(c.blobs, hasLength(1));
      await invoke('removeAttachment', {'id': a.id});
      expect(a.bytes.every((b) => b == 0), true);
      expect(c.blobs, hasLength(1));
      await expectLater(
        invoke('readAttachment', {'id': a.id}),
        throwsFormatException,
      );
      q.updateDraft('seen');
      final stamp = bridge.stamp;
      q.updateDraft('unseen edit');
      await expectLater(
        invoke('newConversation', {'stamp': stamp}),
        throwsFormatException,
      );
      expect(q.draft, 'unseen edit');
    } finally {
      bridge.clear();
      q.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });

  test('detached send returns while upstream waits so stop and local commands can run; revoked late reply is ignored', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-window-wait-',
    );
    final ai = _WaitingAi();
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    final q = AgentConversation(c);
    final binding = WindowConversationBridge(q, active: () => true);
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-only-password',
        usesChinesePassphrase: false,
      );
      q.updateDraft('fixture');
      final consent =
          await binding.invoke(const MethodCall('prepareSend')) as Map;
      await binding
          .invoke(MethodCall('send', {'ticket': consent['ticket']}))
          .timeout(const Duration(seconds: 1));
      expect(q.working, true);
      await binding.invoke(const MethodCall('cancelAgent'));
      await c.lock();
      ai.reply.complete(
        const AiConversationResponse(
          content: '{"reply":"late","cards":[]}',
          output: [],
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(q.messages, isEmpty);
    } finally {
      binding.clear();
      q.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });
}

class _WaitingAi extends RecordingAi implements AiConversationProvider {
  final reply = Completer<AiConversationResponse>();
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) => reply.future;
}
