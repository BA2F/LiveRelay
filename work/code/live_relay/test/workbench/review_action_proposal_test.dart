import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/ai/review_action_proposal.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

class PlanningAi extends RecordingAi implements AiConversationProvider {
  Map<String, Object?>? proposed;
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) async {
    requests.add(request);
    final bundle = request.reviewTargets.where((t) => t.bundle).firstOrNull?.id;
    final reference = request.reviewTargets
        .where((t) => !t.bundle)
        .firstOrNull
        ?.id;
    final text = jsonEncode({
      'reply': '以下仅为整理草案',
      'cards': [
        {
          'title': '建议卡片',
          'content': '待本人核对',
          'kind': 'note',
          'inference': false,
          'actions':
              proposed ??
              {
                'bundle': bundle,
                'references': [?reference],
                'incapacitated': 'summary',
                'deceased': 'full',
                'reason': '按本人所选资料整理',
              },
        },
      ],
    });
    return AiConversationResponse(
      content: text,
      output: [
        {'role': 'assistant', 'content': text},
      ],
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('model actions reject unselected IDs, non-bundles, secret levels and extra operations', () {
    const targets = [
      ReviewTarget('chosen', bundle: false),
      ReviewTarget('bundle', bundle: true),
    ];
    final valid = {
      'bundle': 'bundle',
      'references': ['chosen'],
      'incapacitated': 'hidden',
      'deceased': 'full',
      'reason': 'fixture',
    };
    expect(ReviewActionProposal.parse(valid, targets).plan.bundleId, 'bundle');
    for (final invalid in [
      {
        ...valid,
        'references': ['unselected'],
      },
      {...valid, 'bundle': 'chosen'},
      {...valid, 'deceased': 'secret'},
      {...valid, 'delete': 'chosen'},
      {
        ...valid,
        'references': ['chosen', 'chosen'],
      },
    ]) {
      expect(
        () => ReviewActionProposal.parse(invalid, targets),
        throwsFormatException,
      );
    }
    expect(
      () => ReviewActionProposal.parse(valid, const []),
      throwsFormatException,
    );
  });

  test('proposals remain private until owner adoption; edited plans and original proposals survive confirmation and recovery', () async {
    final root = await Directory.systemTemp.createTemp('liverelay-proposals-');
    final ai = PlanningAi();
    final c = createAppController(
      root,
      NoBiometrics(),
      TestOcr(),
      ai,
      TestAiSettings()..configured = true,
    );
    var q = AgentConversation(c);
    try {
      await c.initialize();
      await c.setupVault(
        password: 'fixture-proposal-password',
        usesChinesePassphrase: false,
      );
      await c.createCard(
        const CardDraft(
          title: '所选组合',
          content: 'fixture bundle',
          kind: CardKind.bundle,
        ),
      );
      final bundle = c.cards.single;
      await c.createCard(
        const CardDraft(title: '所选引用', content: 'fixture reference'),
      );
      final reference = c.cards.firstWhere((card) => card.id != bundle.id);
      await c.createCard(
        const CardDraft(title: '未选择资料', content: 'must not disclose'),
      );
      final unselected = c.cards.firstWhere(
        (card) => ![bundle.id, reference.id].contains(card.id),
      );
      q.attachCard(bundle);
      q.attachCard(reference);
      q.updateDraft('请建议收纳引用及身故完整正文可见');
      ai.proposed = {
        'bundle': bundle.id,
        'references': [unselected.id],
        'incapacitated': 'hidden',
        'deceased': 'full',
      };
      expect(await q.send(q.prepare(q.draft, const [])), isFalse);
      expect(q.messages, isEmpty);
      expect(c.cards.length, 3);
      ai.proposed = null;
      expect(await q.send(q.prepare(q.draft, const [])), isTrue);
      expect(ai.requests.last.reviewTargets.map((t) => t.id).toSet(), {
        bundle.id,
        reference.id,
      });
      final ignored = q.messages.last;
      expect(ignored.actions.single.hasChanges, isFalse);
      await q.accept(ignored);
      final ignoredCard = c.cards.firstWhere((card) => card.title == '建议卡片');
      expect(c.cardReferences.where((r) => r.from == ignoredCard.id), isEmpty);
      expect(
        c.releasePolicies
            .where((p) => p.recordId == ignoredCard.id)
            .every((p) => p.deceased == VisibilityLevel.hidden),
        isTrue,
      );
      final ignoredSource = (await c.cardReviewSource(ignoredCard.id))!;
      expect(ignoredSource.actions.single.hasChanges, isFalse);
      expect(
        ignoredSource.proposals.single!.plan.deceased,
        VisibilityLevel.full,
      );
      ignoredSource.wipe();
      q.attachCard(bundle);
      q.attachCard(reference);
      q.updateDraft('继续提出草案');
      expect(await q.send(q.prepare(q.draft, const [])), isTrue);
      await q.flush();
      q.dispose();
      await c.lock();
      await c.unlockWithPassword('fixture-proposal-password');
      q = AgentConversation(c);
      await q.load();
      final adopted = q.messages.last;
      expect(adopted.actions.single.hasChanges, isFalse);
      q.adoptProposal(adopted, 0);
      q.editActions(
        adopted,
        0,
        ReviewActions(
          bundleId: adopted.actions.single.bundleId,
          referenceIds: adopted.actions.single.referenceIds,
          incapacitated: VisibilityLevel.hidden,
          deceased: VisibilityLevel.summary,
        ),
      );
      q.editSuggestion(adopted, 0, title: '本人改后确认');
      await q.accept(adopted);
      final card = c.cards.firstWhere((c) => c.title == '本人改后确认');
      expect(
        c.cardReferences.where((r) => r.from == card.id).single.to,
        reference.id,
      );
      expect(
        (await c.cardRelations(bundle.id))
            .any((r) => r.fromCardId == bundle.id && r.toCardId == card.id),
        isTrue,
      );
      expect(
        c.releasePolicies.firstWhere((p) => p.recordId == card.id).deceased,
        VisibilityLevel.summary,
      );
      final source = (await c.cardReviewSource(card.id))!;
      expect(source.proposals.single!.plan.deceased, VisibilityLevel.full);
      expect(source.actions.single.deceased, VisibilityLevel.summary);
      source.wipe();
      await q.accept(adopted);
      expect(c.cards.where((c) => c.title == '本人改后确认').length, 1);
    } finally {
      q.dispose();
      await c.lock();
      c.dispose();
      await root.delete(recursive: true);
    }
  });
}
