import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/ai/review_source.dart';
import 'package:live_relay/application/workbench/card_references.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

void main() {
  test('owner plans apply membership, references and visibility atomically once without inheriting target policies', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      final a = await r.createCard(
        const CardDraft(title: 'A', content: 'target'),
      );
      final b = await r.createCard(
        const CardDraft(title: 'B', content: 'member'),
      );
      final bundle = await r.combineCards('collection', [a.id, b.id]);
      await r.saveReleasePolicy(
        ReleasePolicy(
          recordType: 'card',
          recordId: a.id,
          deceased: VisibilityLevel.original,
        ),
      );
      final plan = ReviewActions(
        bundleId: bundle.id,
        referenceIds: [a.id],
        incapacitated: VisibilityLevel.existence,
        deceased: VisibilityLevel.summary,
      );
      final cards = await r.saveReviewedAgentSuggestions(
        'owner-plan',
        'scope',
        [
          const CardDraft(title: 'reviewed', content: 'new body'),
          const CardDraft(title: 'private', content: 'no chosen policy'),
        ],
        providerLabel: 'fixture',
        actions: [plan, const ReviewActions()],
      );
      final links = await CardReferenceStore(r).read();
      expect(links.single.from, cards.first.id);
      expect(links.single.to, a.id);
      final relations = await r.relationsForCard(bundle.id);
      expect(
        relations.where(
          (r) =>
              r.toCardId == cards.first.id &&
              r.kind == RelationKind.bundleMember,
        ),
        hasLength(1),
      );
      final policy = await r.getReleasePolicy('card', cards.first.id);
      expect(policy.incapacitated, VisibilityLevel.existence);
      expect(policy.deceased, VisibilityLevel.summary);
      expect(
        (await r.getReleasePolicy('card', cards.last.id)).deceased,
        VisibilityLevel.hidden,
      );
      expect(
        (await r.getReleasePolicy('card', bundle.id)).deceased,
        VisibilityLevel.hidden,
      );
      await r.trashCard(a.id);
      final repeated = await r.saveReviewedAgentSuggestions(
        'owner-plan',
        'different scope',
        [
          const CardDraft(title: 'different', content: 'different'),
          const CardDraft(title: 'different2', content: 'different'),
        ],
        providerLabel: 'fixture',
        actions: [
          const ReviewActions(deceased: VisibilityLevel.original),
          const ReviewActions(),
        ],
      );
      expect(repeated.map((c) => c.id), cards.map((c) => c.id));
      expect(
        (await r.getReleasePolicy('card', cards.first.id)).deceased,
        VisibilityLevel.summary,
      );
      expect((await CardReferenceStore(r).read()).length, 1);
      expect((await r.relationsForCard(bundle.id)).length, relations.length);
    } finally {
      await r.close();
    }
  });

  test('late receipt storage failure rolls back card, plans, source and audit; stale choices fail closed', () async {
    final db = AppDatabase.inMemory();
    final r = SqliteVaultRepository(db);
    try {
      final a = await r.createCard(
        const CardDraft(title: 'A', content: 'body'),
      );
      final b = await r.createCard(
        const CardDraft(title: 'B', content: 'body'),
      );
      final bundle = await r.combineCards('collection', [a.id, b.id]);
      final plan = ReviewActions(
        bundleId: bundle.id,
        referenceIds: [a.id],
        deceased: VisibilityLevel.full,
      );
      final source = ReviewSource(
        reviewId: 'rollback-actions',
        providerLabel: 'fixture',
        confirmedAt: DateTime.utc(2026),
        inputs: const [ReviewSourceInput('private scope', [])],
        reply: 'reply',
        actions: [plan],
      );
      await db.customStatement(
        "CREATE TEMP TRIGGER reject_review_receipt BEFORE INSERT ON vault_local_state WHEN NEW.name = 'agent.review.rollback-actions' BEGIN SELECT RAISE(ABORT, 'fixture receipt failure'); END",
      );
      await expectLater(
        r.saveReviewedAgentSuggestions(
          'rollback-actions',
          'scope',
          [const CardDraft(title: 'rollback', content: 'body')],
          providerLabel: 'fixture',
          actions: [plan],
          reviewSource: source,
        ),
        throwsA(isA<Exception>()),
      );
      expect((await r.listCards()).length, 3);
      expect(await CardReferenceStore(r).read(), isEmpty);
      expect((await r.relationsForCard(bundle.id)).length, 2);
      expect(await r.listReleasePolicies(), isEmpty);
      expect(await r.readLocalValue(source.storageKey), isNull);
      expect(await r.readLocalValue('agent.review.rollback-actions'), isNull);
      expect(await r.readLocalValue('agent.plan.rollback-actions'), isNull);
      await r.trashCard(bundle.id);
      await expectLater(
        r.saveReviewedAgentSuggestions(
          'stale-actions',
          'scope',
          [const CardDraft(title: 'fail', content: 'body')],
          providerLabel: 'fixture',
          actions: [plan],
        ),
        throwsFormatException,
      );
      expect((await r.listCards()).length, 2);
      expect(await r.readLocalValue('agent.review.stale-actions'), isNull);
      expect(
        () => ReviewActions(referenceIds: [a.id, a.id]).validate(),
        throwsFormatException,
      );
      expect(
        () => const ReviewActions(deceased: VisibilityLevel.secret).validate(),
        throwsFormatException,
      );
    } finally {
      await r.close();
    }
  });
}
