import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ai/review_source.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../support/verification_fakes.dart';

ReviewSource source(String id, {bool large = false}) => ReviewSource(
  reviewId: id,
  providerLabel: 'fixture',
  confirmedAt: DateTime.utc(2026, 10, 5),
  reply: 'model fixture reply',
  inputs: [
    ReviewSourceInput('中文🙂' * (large ? 5000 : 1), [
      ConversationAttachment.read(
        'fixture.pdf',
        Uint8List.fromList(
          utf8.encode('%PDF-fixture${'x' * (large ? 700000 : 1)}'),
        ),
      ),
    ]),
    ReviewSourceInput('y' * 20000, const []),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('full review sources survive backup and revisions; repeat receipt preserves first evidence', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    final restored = SqliteVaultRepository(AppDatabase.inMemory());
    final evidence = source('evidence-review', large: true);
    try {
      final cards = await r.saveReviewedAgentSuggestions(
        evidence.reviewId,
        evidence.inputs.map((i) => i.text).join('\n'),
        [const CardDraft(title: 'confirmed', content: 'summary')],
        providerLabel: 'fixture',
        reviewSource: evidence,
      );
      expect(await r.readLocalValue(evidence.storageKey), contains('chunked'));
      expect(await r.listBlobs(), isEmpty);
      final first = (await r.cardReviewSource(cards.single.id))!;
      expect(first.inputs.first.text, evidence.inputs.first.text);
      expect(
        first.inputs.first.attachments.single.bytes,
        evidence.inputs.first.attachments.single.bytes,
      );
      first.wipe();
      final repeated = await r.saveReviewedAgentSuggestions(
        evidence.reviewId,
        'changed input',
        [const CardDraft(title: 'different', content: 'different')],
        providerLabel: 'fixture',
        reviewSource: source(evidence.reviewId),
      );
      expect(repeated.single.id, cards.single.id);
      await r.updateCard(
        cards.single.id,
        const CardDraft(title: 'edited', content: 'later'),
      );
      final snapshot = await r.exportLocalState();
      await restored.importLocalState(snapshot);
      snapshot.fillRange(0, snapshot.length, 0);
      final after = (await restored.cardReviewSource(cards.single.id))!;
      expect(after.inputs.first.text, evidence.inputs.first.text);
      expect(
        after.inputs.first.attachments.single.bytes.length,
        greaterThan(700000),
      );
      expect(after.reply, 'model fixture reply');
      expect(
        (await restored.getReleasePolicy('card', cards.single.id)).deceased,
        VisibilityLevel.hidden,
      );
      after.wipe();
    } finally {
      evidence.wipe();
      await r.close();
      await restored.close();
    }
  });

  test('missing originals and invalid drafts roll back cards, source chunks and receipts', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    final evidence = source('rollback-review', large: true);
    try {
      await expectLater(
        r.saveReviewedAgentSuggestions(
          evidence.reviewId,
          'scope',
          [const CardDraft(title: 'rollback', content: 'body')],
          providerLabel: 'fixture',
          originalIds: ['missing'],
          reviewSource: evidence,
        ),
        throwsFormatException,
      );
      expect(await r.listCards(), isEmpty);
      expect(await r.readLocalValue(evidence.storageKey), isNull);
      expect(await r.readLocalValue('${evidence.storageKey}.part0'), isNull);
      expect(
        await r.readLocalValue('agent.review.${evidence.reviewId}'),
        isNull,
      );
      await expectLater(
        r.saveReviewedAgentSuggestions(
          evidence.reviewId,
          'scope',
          [
            const CardDraft(title: 'valid', content: 'body'),
            const CardDraft(title: '', content: 'invalid'),
          ],
          providerLabel: 'fixture',
          reviewSource: evidence,
        ),
        throwsFormatException,
      );
      expect(await r.listCards(), isEmpty);
      expect(await r.readLocalValue(evidence.storageKey), isNull);
      final invalid = jsonDecode(evidence.encode()) as Map;
      invalid['inputs'][0]['attachments'][0]['kind'] = 'image';
      expect(
        () => ReviewSource.decode(jsonEncode(invalid)),
        throwsFormatException,
      );
    } finally {
      evidence.wipe();
      await r.close();
    }
  });

  test(
    'new conversation and lock do not erase confirmed card attachment evidence',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'liverelay-review-source-',
      );
      final c = createAppController(
        dir,
        NoBiometrics(),
        TestOcr(),
        RecordingConversationAi(),
        TestAiSettings(),
      );
      final q = AgentConversation(c);
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-review-password',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(title: 'selected', content: 'old card body'),
        );
        final selected = c.cards.single;
        q.attachCard(selected);
        final attachment = q.attachments.removeLast();
        q.messages.add(
          ConversationMessage(
            'user',
            'private input',
            attachments: [attachment],
          ),
        );
        final message = ConversationMessage(
          'assistant',
          'fixture reply',
          providerLabel: 'fixture',
          suggestions: [
            const AiCardSuggestion(
              title: 'reviewed',
              content: 'summary',
              kind: CardKind.note,
              isInference: false,
            ),
          ],
        );
        q.messages.add(message);
        q.editActions(
          message,
          0,
          ReviewActions(
            referenceIds: [selected.id],
            deceased: VisibilityLevel.summary,
          ),
        );
        await q.flush();
        final restored = AgentConversation(c);
        await restored.load();
        expect(restored.messages.last.actions.single.referenceIds, [
          selected.id,
        ]);
        expect(
          restored.messages.last.actions.single.deceased,
          VisibilityLevel.summary,
        );
        restored.dispose();
        await q.accept(message);
        expect(q.error, isNull);
        final id = c.cards.singleWhere((c) => c.title == 'reviewed').id;
        // Simulate a process stopping after the card transaction, before the
        // accepted conversation state reached disk.
        message.accepted = false;
        q.editActions(
          message,
          0,
          const ReviewActions(deceased: VisibilityLevel.original),
        );
        await q.accept(message);
        expect(q.error, isNull);
        expect(message.actions.single.referenceIds, [selected.id]);
        expect(message.actions.single.deceased, VisibilityLevel.summary);
        expect(c.cards.length, 2);
        await q.newConversation();
        expect(attachment.bytes.every((b) => b == 0), true);
        await c.updateCard(
          selected.id,
          const CardDraft(title: 'selected', content: 'new card body'),
        );
        await c.lock();
        await c.unlockWithPassword('fictional-review-password');
        final after = (await c.cardReviewSource(id))!;
        expect(after.inputs.single.text, 'private input');
        expect(
          after.inputs.single.attachments.single.text,
          'selected\nold card body',
        );
        expect(
          after.inputs.single.attachments.single.cardRevision,
          selected.revisionNumber,
        );
        expect(c.blobs, isEmpty);
        expect(after.actions.single.referenceIds, [selected.id]);
        expect(after.actions.single.deceased, VisibilityLevel.summary);
        expect(
          (await c.releasePolicy('card', id)).deceased,
          VisibilityLevel.summary,
        );
        after.wipe();
      } finally {
        q.dispose();
        await c.lock();
        c.dispose();
        await dir.delete(recursive: true);
      }
    },
  );
}
