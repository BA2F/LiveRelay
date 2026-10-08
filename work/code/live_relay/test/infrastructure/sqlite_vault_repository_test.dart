import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

void main() {
  late AppDatabase database;
  late SqliteVaultRepository repository;

  setUp(() {
    database = AppDatabase.inMemory();
    repository = SqliteVaultRepository(database);
  });

  tearDown(() => repository.close());

  test(
    'card updates append revisions instead of overwriting history',
    () async {
      final card = await repository.createCard(
        const CardDraft(title: '房产证位置', content: '在卧室衣柜顶层'),
      );
      await repository.updateCard(
        card.id,
        const CardDraft(title: '房产证位置', content: '已移到书房保险箱'),
        changeNote: '搬家后更新',
      );

      final history = await repository.cardHistory(card.id);
      expect(history, hasLength(2));
      expect(history.first.content, '已移到书房保险箱');
      expect(history.last.content, '在卧室衣柜顶层');
    },
  );

  test('split preserves predecessor and combine only links members', () async {
    final original = await repository.createCard(
      const CardDraft(
        title: '待整理大卡片',
        content: '水费账号与宠物照护信息',
        status: CardStatus.draft,
      ),
    );
    final parts = await repository.splitCard(original.id, const [
      CardDraft(title: '水费账号', content: '户号 123'),
      CardDraft(title: '宠物照护', content: '每天两次喂食'),
    ]);
    final bundle = await repository.combineCards(
      '家庭日常',
      parts.map((card) => card.id).toList(),
    );

    expect((await repository.getCard(original.id))!.status, CardStatus.split);
    expect(await repository.relationsForCard(bundle.id), hasLength(2));
    expect(await repository.getCard(parts.first.id), isNotNull);
  });

  test(
    'Agent batches preserve the source and roll back an invalid later card',
    () async {
      await expectLater(
        repository.saveAgentSuggestions('本人原文', const [
          CardDraft(title: '有效卡片', content: '内容'),
          CardDraft(title: '', content: '无效标题'),
        ], providerLabel: 'fictional-agent'),
        throwsA(isA<FormatException>()),
      );
      expect(await repository.listCards(), isEmpty);
      final cards = await repository.saveAgentSuggestions('本人原文', const [
        CardDraft(title: '整理结果', content: '改写内容', status: CardStatus.confirmed),
      ], providerLabel: 'fictional-agent');
      expect(cards.single.status, CardStatus.draft);
      final source = (await repository.cardSources(cards.single.id)).single;
      expect(source.excerpt, '本人原文');
      expect(source.kind, SourceKind.aiGenerated);
    },
  );

  test('credential keeps old secret until explicit purge', () async {
    final entry = await repository.saveCredential(
      const CredentialDraft(
        title: '邮箱',
        username: 'owner@example.com',
        secret: 'old-secret',
      ),
    );
    await repository.saveCredential(
      const CredentialDraft(
        title: '邮箱',
        username: 'owner@example.com',
        secret: 'new-secret',
      ),
      id: entry.id,
    );

    final history = await repository.credentialHistory(entry.id);
    expect(history.map((revision) => revision.secret), [
      'new-secret',
      'old-secret',
    ]);

    await repository.purgeCredential(entry.id);
    expect(await repository.credentialHistory(entry.id), isEmpty);
  });

  test(
    'encrypted original and OCR draft keep provenance and geometry',
    () async {
      final blob = VaultBlob(
        id: 'blob-1',
        originalName: '证件照片.png',
        mediaKind: BlobMediaKind.image,
        mimeType: 'image/png',
        relativePath: 'blobs/blob-1.blob',
        byteLength: 1234,
        sha256: 'digest',
        createdAt: DateTime.utc(2026, 9, 23),
      );
      final sourceCard = await repository.registerBlob(blob);
      final ocrCard = await repository.saveOcrResult(
        blob.id,
        const OcrResult(
          text: '姓名 张三',
          lines: [
            OcrLine(
              text: '姓名 张三',
              left: 10,
              top: 20,
              right: 120,
              bottom: 45,
              order: 0,
              confidence: 0.98,
            ),
          ],
        ),
      );

      expect(sourceCard.status, CardStatus.confirmed);
      expect(ocrCard.status, CardStatus.draft);
      final stored = (await repository.listBlobs()).single;
      expect(stored.ocrText, '姓名 张三');
      expect(stored.ocrLines.single.confidence, 0.98);
      final history = await repository.cardHistory(ocrCard.id);
      expect(history.single.sourceKind, SourceKind.ocrDerived);

      await repository.saveSensitiveMarks(blob.id, const [
        SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.account),
      ]);
      final marked = (await repository.listBlobs()).single;
      expect(marked.sensitiveMarks.single.kind, SensitiveFieldKind.account);

      final aiCards = await repository.saveAiSuggestions(blob.id, const [
        CardDraft(
          title: 'AI 整理草稿',
          content: '姓名 张三',
          status: CardStatus.draft,
          tags: ['AI', '待确认'],
        ),
      ], providerLabel: '获授权云 AI · test-model');
      expect(aiCards.single.status, CardStatus.draft);
      expect(
        (await repository.cardHistory(aiCards.single.id)).single.sourceKind,
        SourceKind.aiGenerated,
      );
    },
  );

  test(
    'Edge credential batch import is atomic and preserves secrets',
    () async {
      final count = await repository.importCredentials(const [
        CredentialDraft(title: 'A', username: 'alice', secret: '0012'),
        CredentialDraft(title: 'B', username: 'bob', secret: 'comma,value'),
      ]);
      expect(count, 2);
      expect(
        (await repository.listCredentials())
            .map((entry) => entry.secret)
            .toSet(),
        {'0012', 'comma,value'},
      );
    },
  );

  test('release remains owner-only until explicit policy is saved', () async {
    final card = await repository.createCard(
      const CardDraft(title: '保险联系人', content: '95500'),
    );
    final initial = await repository.getReleasePolicy('card', card.id);
    expect(initial.visibleAt(LifeState.incapacitated), VisibilityLevel.hidden);

    await repository.saveReleasePolicy(
      ReleasePolicy(
        recordType: 'card',
        recordId: card.id,
        incapacitated: VisibilityLevel.summary,
        deceased: VisibilityLevel.full,
      ),
    );
    final updated = await repository.getReleasePolicy('card', card.id);
    expect(updated.visibleAt(LifeState.deceased), VisibilityLevel.full);
  });

  test('life-state history distinguishes transition from demo reset', () async {
    await repository.transitionLifeState(
      LifeState.incapacitated,
      reason: '演示临时失能',
    );
    await repository.transitionLifeState(LifeState.deceased, reason: '演示身故');
    await repository.resetLifeStateSimulation(reason: '重新开始演示');

    expect(await repository.currentLifeState(), LifeState.active);
    final history = await repository.lifeStateHistory();
    expect(history, hasLength(3));
    expect(history.first.reason, '重新开始演示');
  });
  test(
    'invalid split is atomic; recycled cards cannot be confirmed or combined',
    () async {
      final a = await repository.createCard(
        const CardDraft(
          title: 'Public predecessor',
          content: 'Public body',
          status: CardStatus.draft,
        ),
      );
      final b = await repository.createCard(
        const CardDraft(title: 'Public member', content: 'Public body'),
      );
      await expectLater(
        repository.splitCard(a.id, const [
          CardDraft(title: 'Valid child', content: 'Public body'),
          CardDraft(title: '', content: 'Invalid child'),
        ]),
        throwsFormatException,
      );
      expect((await repository.getCard(a.id))!.status, CardStatus.draft);
      expect(await repository.cardHistory(a.id), hasLength(1));
      expect(await repository.listCards(), hasLength(2));
      expect(await repository.relationsForCard(a.id), isEmpty);
      await repository.trashCard(b.id);
      await expectLater(
        repository.combineCards('Public bundle', [a.id, b.id]),
        throwsStateError,
      );
      await expectLater(repository.confirmCard(b.id), throwsStateError);
      expect(await repository.listCards(), hasLength(1));
      expect(await repository.cardHistory(b.id), hasLength(1));
    },
  );
  test('reference changes validate current facts atomically and retain prior links', () async {
    final cards = <LifeCard>[];
    for (final name in ['A', 'B', 'C']) {
      cards.add(
        await repository.createCard(
          CardDraft(title: 'Public $name', content: 'Public body'),
        ),
      );
    }
    await repository.setCardReferences(cards[0].id, [cards[1].id]);
    await repository.trashCard(cards[2].id);
    await expectLater(
      repository.setCardReferences(cards[0].id, [cards[2].id]),
      throwsFormatException,
    );
    expect((await repository.cardReferences()).single.to, cards[1].id);
    await repository.restoreCard(cards[2].id);
    await repository.setCardReferences(cards[0].id, [cards[2].id, cards[2].id]);
    expect((await repository.cardReferences()).single.to, cards[2].id);
    expect(
      await repository.readLocalValue('workbench.references.v1'),
      contains('"version":1'),
    );
  });
  test('life transition and audit commit together and simultaneous duplicates serialize', () async {
    await database.customStatement(
      "CREATE TRIGGER fixture_fail_audit BEFORE INSERT ON audit_events WHEN NEW.action='transition' BEGIN SELECT RAISE(ABORT, 'fixture audit denied'); END",
    );
    await expectLater(
      repository.transitionLifeState(
        LifeState.incapacitated,
        reason: 'Public fixture',
      ),
      throwsA(anything),
    );
    expect(await repository.currentLifeState(), LifeState.active);
    expect(await repository.lifeStateHistory(), isEmpty);
    await database.customStatement('DROP TRIGGER fixture_fail_audit');
    Future<Object?> attempt() async {
      try {
        await repository.transitionLifeState(
          LifeState.incapacitated,
          reason: 'Public fixture',
        );
        return null;
      } on Object catch (e) {
        return e;
      }
    }

    final results = await Future.wait([attempt(), attempt()]);
    expect(results.where((v) => v == null), hasLength(1));
    expect(await repository.lifeStateHistory(), hasLength(1));
  });
}
