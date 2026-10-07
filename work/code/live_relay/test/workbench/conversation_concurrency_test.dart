import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/application/workbench/workbench_runtime.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

/// A deliberately pending upstream, containing only fixture text.
class PendingConversationAi extends RecordingAi
    implements AiConversationProvider {
  final entered = Completer<void>();
  final reply = Completer<AiConversationResponse>();
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) {
    requests.add(request);
    entered.complete();
    return reply.future;
  }

  void complete() {
    if (!reply.isCompleted) {
      reply.complete(
        const AiConversationResponse(
          content: '{"reply":"fictional pending reply","cards":[]}',
          output: [
            {
              'role': 'assistant',
              'content': '{"reply":"fictional pending reply","cards":[]}',
            },
          ],
        ),
      );
    }
  }
}

class _PendingKey extends TestAiSettings {
  bool pending = false;
  final entered = Completer<void>();
  final key = Completer<String?>();
  @override
  Future<String?> readApiKey() {
    if (!pending) return super.readApiKey();
    entered.complete();
    return key.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('pending network leaves local autosave and save-before-lock available; no overlapping Agent or late reply', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-network-save-',
    );
    final ai = PendingConversationAi();
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    final runtime = WorkbenchRuntime(c);
    Future<bool>? pending;
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-network-save',
        usesChinesePassphrase: false,
      );
      await c.createCard(const CardDraft(title: 'before', content: 'fixture'));
      await runtime.load();
      final q = runtime.conversation;
      q.updateDraft('待答复的虚构资料');
      pending = q.send(q.prepare(q.draft, []));
      await ai.entered.future;
      expect(c.isBusy, false);
      expect(c.isAgentBusy, true);
      expect(q.working, true);
      await expectLater(
        c.converse('unapproved overlapping request', []),
        throwsFormatException,
      );
      await expectLater(
        c.proposeAgentDrafts('unapproved tool request', []),
        throwsStateError,
      );
      expect(ai.requests, hasLength(1));
      final card = c.cards.single;
      runtime.edits.edit(
        runtime.edits.session(card),
        title: 'saved during upstream wait',
      );
      await runtime.edits.flush();
      expect(c.cards.single.title, 'saved during upstream wait');
      expect(runtime.edits.hasUnsaved, false);
      expect(ai.reply.isCompleted, false);
      await runtime.flush();
      expect(await c.readConversationState(), contains('待答复的虚构资料'));
      await runtime.saveAndLock();
      expect(c.isUnlocked, false);
      expect(ai.requests.single.cancellation!.isCancelled, true);
      await c.unlockWithPassword('fixture-network-save');
      ai.complete();
      expect(await pending, false);
      expect(q.messages, isEmpty);
      expect(c.isAgentBusy, false);
      expect(c.cards.single.title, 'saved during upstream wait');
      final reopened = AgentConversation(c);
      await reopened.load();
      expect(reopened.draft, '待答复的虚构资料');
      reopened.dispose();
    } finally {
      ai.complete();
      if (pending != null) await pending;
      runtime.dispose();
      if (c.isUnlocked) await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });

  test('configuration changes during upstream wait discard result and retain the local input', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-network-config-',
    );
    final ai = PendingConversationAi();
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    final q = AgentConversation(c);
    Future<bool>? pending;
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-network-config',
        usesChinesePassphrase: false,
      );
      q.updateDraft('fixture input retained');
      pending = q.send(q.prepare(q.draft, []));
      await ai.entered.future;
      c.aiConfigurationGeneration++;
      ai.complete();
      expect(await pending, false);
      expect(q.error, contains('配置已变化'));
      expect(q.draft, 'fixture input retained');
      expect(q.messages, isEmpty);
      expect(c.isBusy, false);
      expect(c.isAgentBusy, false);
    } finally {
      ai.complete();
      if (pending != null) await pending;
      q.dispose();
      if (c.isUnlocked) await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });

  test(
    'configuration changed while reading a key prevents any upstream request',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-pending-key-',
      );
      final ai = PendingConversationAi();
      final settings = _PendingKey()..configured = true;
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        settings,
      );
      final q = AgentConversation(c);
      Future<bool>? pending;
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-pending-key',
          usesChinesePassphrase: false,
        );
        settings.pending = true;
        q.updateDraft('fixture scope');
        pending = q.send(q.prepare(q.draft, []));
        await settings.entered.future;
        c.aiConfigurationGeneration++;
        settings.key.complete('fixture-key');
        expect(await pending, false);
        expect(ai.requests, isEmpty);
        expect(q.draft, 'fixture scope');
        expect(q.error, contains('配置已变化'));
      } finally {
        if (!settings.key.isCompleted) settings.key.complete(null);
        ai.complete();
        if (pending != null) await pending;
        q.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
