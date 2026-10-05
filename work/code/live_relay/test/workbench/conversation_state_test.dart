import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'unreadable conversation is retained until an explicit new conversation',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'liverelay-conversation-state-',
      );
      final c = createAppController(
        dir,
        NoBiometrics(),
        TestOcr(),
        RecordingConversationAi(),
        TestAiSettings()..configured = true,
      );
      final q = AgentConversation(c);
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-only-password',
          usesChinesePassphrase: false,
        );
        await c.writeConversationState('{"version":99,"future":"retain"}');
        await expectLater(q.load(), throwsFormatException);
        q.updateDraft('new local input');
        await expectLater(q.flush(), throwsFormatException);
        expect(
          await c.readConversationState(),
          '{"version":99,"future":"retain"}',
        );
        await q.newConversation();
        expect(await c.readConversationState(), contains('"version":1'));
      } finally {
        q.dispose();
        await c.lock();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
  test('reviewed send scope is invalid after configuration changes or locking; late replies are discarded', () async {
    final dir = await Directory.systemTemp.createTemp(
      'liverelay-conversation-cancel-',
    );
    final ai = _DelayedAi();
    final c = createAppController(
      dir,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    final q = AgentConversation(c);
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-only-password',
        usesChinesePassphrase: false,
      );
      q.updateDraft('private fixture');
      final oldScope = q.prepare(q.draft, [
        const SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.secret),
      ]);
      c.aiSettings = const AiProviderSettings(
        endpoint: 'https://different.invalid/chat',
        model: 'different',
        hasApiKey: true,
      );
      expect(await q.send(oldScope), false);
      expect(ai.requests, isEmpty);
      q.updateDraft('private fixture');
      final pending = q.send(
        q.prepare(q.draft, [
          const SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.secret),
        ]),
      );
      for (var i = 0; i < 100 && ai.requests.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(ai.requests.single.redactedText, '[[TURN1_SECRET_01]]');
      await c.lock();
      expect(q.draft, isEmpty);
      expect(q.messages, isEmpty);
      ai.reply.complete(
        const AiConversationResponse(
          content: '{"reply":"late","cards":[]}',
          output: [],
        ),
      );
      expect(await pending, false);
      expect(q.messages, isEmpty);
      await c.unlockWithPassword('fixture-only-password');
      expect(await q.send(oldScope), false);
      expect(ai.requests.length, 1);
    } finally {
      q.dispose();
      await c.lock();
      c.dispose();
      await dir.delete(recursive: true);
    }
  });
}

class _DelayedAi extends RecordingAi implements AiConversationProvider {
  final reply = Completer<AiConversationResponse>();
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) {
    requests.add(request);
    return reply.future;
  }
}
