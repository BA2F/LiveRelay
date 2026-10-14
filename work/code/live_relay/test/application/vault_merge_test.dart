import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/merge/card_merge_planner.dart';
import 'package:live_relay/application/vault_backup_service.dart';
import 'package:live_relay/application/vault_merge_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/vault_merge.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../support/session_fakes.dart';

LifeCard fixtureCard(
  String id, {
  String title = '虚构卡片',
  String content = 'fixture',
  CardKind kind = CardKind.note,
  CardStatus status = CardStatus.confirmed,
  DateTime? deletedAt,
  int revisionNumber = 1,
}) => LifeCard(
  id: id,
  title: title,
  content: content,
  kind: kind,
  status: status,
  tags: const ['标签'],
  createdAt: DateTime.utc(2026, 10, 14, 6),
  updatedAt: DateTime.utc(2026, 10, 14, 6),
  deletedAt: deletedAt,
  revisionNumber: revisionNumber,
);

CardRevision fixtureRevision(
  String cardId,
  int number, {
  String? title,
  String? content,
  List<String> tags = const ['标签'],
  CardStatus status = CardStatus.confirmed,
  SourceKind sourceKind = SourceKind.ownerInput,
  String sourceLabel = '本人修改',
  String changeNote = '更新卡片',
  DateTime? createdAt,
}) => CardRevision(
  id: number,
  cardId: cardId,
  number: number,
  title: title ?? '虚构卡片',
  content: content ?? 'fixture-v$number',
  tags: tags,
  status: status,
  sourceKind: sourceKind,
  sourceLabel: sourceLabel,
  changeNote: changeNote,
  createdAt: createdAt ?? DateTime.utc(2026, 10, 14, 7, 0, number),
);

VaultBlob fixtureBlob(String id, String relativePath) => VaultBlob(
  id: id,
  originalName: '$id.txt',
  mediaKind: BlobMediaKind.other,
  mimeType: 'text/plain',
  relativePath: relativePath,
  byteLength: 8,
  sha256: 'fixture-$id',
  createdAt: DateTime.utc(2026, 10, 14, 6),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final mergedAt = DateTime.utc(2026, 10, 14, 9);

  group('card merge planner', () {
    test('common prefix compares revision number and fingerprint', () async {
      final shared = fixtureRevision('c', 1);
      expect(
        await commonRevisionPrefix(
          [shared, fixtureRevision('c', 2)],
          [shared, fixtureRevision('c', 2), fixtureRevision('c', 3)],
        ),
        2,
      );
      expect(
        await commonRevisionPrefix(
          [shared, fixtureRevision('c', 2)],
          [shared, fixtureRevision('c', 2, content: '另一台设备的修改')],
        ),
        1,
      );
      // The same instant expressed in local time fingerprints identically.
      final utc = fixtureRevision(
        'c',
        1,
        createdAt: DateTime.utc(2026, 10, 14, 7),
      );
      final local = fixtureRevision(
        'c',
        1,
        createdAt: DateTime.utc(2026, 10, 14, 7).toLocal(),
      );
      expect(
        mergeRevisionFingerprintInput(utc),
        mergeRevisionFingerprintInput(local),
      );
      expect(
        await mergeRevisionFingerprint(utc),
        await mergeRevisionFingerprint(local),
      );
    });

    test('fast-forward appends the other suffix and adopts its head', () async {
      final decision = await planCardMerge(
        local: CardMergeSide(
          card: fixtureCard('c'),
          revisions: [fixtureRevision('c', 1)],
        ),
        foreign: CardMergeSide(
          card: fixtureCard('c', kind: CardKind.location, revisionNumber: 2),
          revisions: [
            fixtureRevision('c', 1),
            fixtureRevision('c', 2, content: '对方的新内容'),
          ],
        ),
        mergedAt: mergedAt,
      );
      expect(decision.action, CardMergeAction.fastForward);
      expect(decision.conflict, isNull);
      final record = decision.record!;
      expect(record.card.content, '对方的新内容');
      expect(record.card.kind, CardKind.location);
      expect(record.card.revisionNumber, 2);
      expect(record.appendedRevisions.single.number, 2);
      expect(record.appendedRevisions.single.changeNote, '更新卡片');
    });

    test(
      'fast-forward replays the per-revision originals of the other side',
      () async {
        final decision = await planCardMerge(
          local: CardMergeSide(
            card: fixtureCard('c'),
            revisions: [fixtureRevision('c', 1)],
          ),
          foreign: CardMergeSide(
            card: fixtureCard('c', revisionNumber: 2),
            revisions: [
              fixtureRevision('c', 1),
              fixtureRevision('c', 2, changeNote: '添加原件引用 · 图纸.pdf'),
            ],
            currentOriginals: ['b1'],
            originalSnapshots: {
              1: const [],
              2: const ['b1'],
            },
            originalLabels: {
              'b1': (label: '本人引用 · 图纸.pdf', kind: SourceKind.ownerInput),
            },
          ),
          mergedAt: mergedAt,
        );
        final record = decision.record!;
        expect(record.currentOriginals, ['b1']);
        expect(record.revisionOriginals[2], ['b1']);
        final appended = record.appendedRevisions.single;
        expect(appended.originalBlobId, 'b1');
        expect(appended.originalSourceLabel, '本人引用 · 图纸.pdf');
      },
    );

    test('fork appends the other segment, a reaffirm and a marker', () async {
      final decision = await planCardMerge(
        local: CardMergeSide(
          card: fixtureCard('c', content: '本机修改', revisionNumber: 2),
          revisions: [
            fixtureRevision('c', 1),
            fixtureRevision('c', 2, content: '本机修改'),
          ],
        ),
        foreign: CardMergeSide(
          card: fixtureCard('c', content: '对方修改', revisionNumber: 2),
          revisions: [
            fixtureRevision('c', 1),
            fixtureRevision('c', 2, content: '对方修改'),
          ],
          currentOriginals: ['b9'],
          originalSnapshots: {
            2: const ['b9'],
          },
        ),
        mergedAt: mergedAt,
      );
      expect(decision.action, CardMergeAction.fork);
      final record = decision.record!;
      expect(record.card.content, '本机修改');
      expect(record.card.revisionNumber, 4);
      expect(record.appendedRevisions.map((r) => r.number), [3, 4]);
      expect(record.appendedRevisions[0].content, '对方修改');
      expect(record.appendedRevisions[0].changeNote, startsWith('来自另一台设备：'));
      expect(record.appendedRevisions[1].content, '本机修改');
      expect(record.appendedRevisions[1].changeNote, '合并：暂保留本机版');
      expect(record.currentOriginals, isNull);
      expect(record.revisionOriginals[3], ['b9']);
      expect(decision.conflict!.kind, MergeConflictKind.fork);
      expect(decision.conflict!.foreignHead, 3);
    });

    test('foreign deletion of an unchanged card is adopted', () async {
      final decision = await planCardMerge(
        local: CardMergeSide(
          card: fixtureCard('c'),
          revisions: [fixtureRevision('c', 1)],
        ),
        foreign: CardMergeSide(
          card: fixtureCard('c', deletedAt: DateTime.utc(2026, 10, 14, 8)),
          revisions: [fixtureRevision('c', 1)],
        ),
        mergedAt: mergedAt,
      );
      expect(decision.action, CardMergeAction.adoptDeletion);
      expect(decision.record!.card.deletedAt, mergedAt);
      expect(decision.conflict, isNull);
    });

    test('foreign deletion with local changes keeps local and marks', () async {
      final decision = await planCardMerge(
        local: CardMergeSide(
          card: fixtureCard('c', content: '本机修改', revisionNumber: 2),
          revisions: [
            fixtureRevision('c', 1),
            fixtureRevision('c', 2, content: '本机修改'),
          ],
        ),
        foreign: CardMergeSide(
          card: fixtureCard('c', deletedAt: DateTime.utc(2026, 10, 14, 8)),
          revisions: [fixtureRevision('c', 1)],
        ),
        mergedAt: mergedAt,
      );
      expect(decision.action, CardMergeAction.keepLocal);
      expect(decision.record, isNull);
      expect(decision.conflict!.foreignDeleted, isTrue);
      expect(decision.conflict!.foreignHead, isNull);
    });

    test(
      'local deletion with foreign changes keeps deletion and marks',
      () async {
        final decision = await planCardMerge(
          local: CardMergeSide(
            card: fixtureCard('c', deletedAt: DateTime.utc(2026, 10, 14, 8)),
            revisions: [fixtureRevision('c', 1)],
          ),
          foreign: CardMergeSide(
            card: fixtureCard('c', content: '对方修改', revisionNumber: 2),
            revisions: [
              fixtureRevision('c', 1),
              fixtureRevision('c', 2, content: '对方修改'),
            ],
          ),
          mergedAt: mergedAt,
        );
        expect(decision.action, CardMergeAction.fork);
        final record = decision.record!;
        expect(record.card.deletedAt, DateTime.utc(2026, 10, 14, 8));
        expect(decision.conflict!.localDeleted, isTrue);
        expect(decision.conflict!.foreignHead, 2);
        expect(decision.conflict!.kind, MergeConflictKind.localDeleted);
      },
    );

    test('unchanged and one-sided cards settle without writes', () async {
      final shared = CardMergeSide(
        card: fixtureCard('c'),
        revisions: [fixtureRevision('c', 1)],
      );
      expect(
        (await planCardMerge(
          local: shared,
          foreign: CardMergeSide(
            card: fixtureCard('c'),
            revisions: [fixtureRevision('c', 1)],
          ),
          mergedAt: mergedAt,
        )).action,
        CardMergeAction.unchanged,
      );
      expect(
        (await planCardMerge(
          local: shared,
          foreign: const CardMergeSide(),
          mergedAt: mergedAt,
        )).action,
        CardMergeAction.unchanged,
      );
      final import = await planCardMerge(
        local: const CardMergeSide(),
        foreign: CardMergeSide(
          card: fixtureCard('f', title: '对方独有'),
          revisions: [fixtureRevision('f', 1, title: '对方独有', content: '对方内容')],
          currentOriginals: const ['b2'],
          originalSnapshots: {1: const []},
          originalLabels: const {},
        ),
        mergedAt: mergedAt,
      );
      expect(import.action, CardMergeAction.importCard);
      expect(import.record!.card.id, 'f');
      expect(import.record!.appendedRevisions.single.number, 1);
      expect(
        (await planCardMerge(
          local: const CardMergeSide(),
          foreign: CardMergeSide(
            card: fixtureCard('f', deletedAt: DateTime.utc(2026, 10, 14, 8)),
            revisions: [fixtureRevision('f', 1)],
          ),
          mergedAt: mergedAt,
        )).action,
        CardMergeAction.unchanged,
      );
    });
  });

  group('applyVaultMergePlan', () {
    late AppDatabase database;
    late SqliteVaultRepository repository;

    setUp(() {
      database = AppDatabase.inMemory();
      repository = SqliteVaultRepository(database);
    });

    tearDown(() => repository.close());

    test(
      'writes imports, appends, binding, relations, references and ledger',
      () async {
        final importedBlob = fixtureBlob('b1', 'blobs/b1.blob');
        final local = await repository.createCard(
          const CardDraft(title: '本机卡片', content: '本机内容'),
        );
        await repository.updateCard(
          local.id,
          const CardDraft(title: '本机卡片', content: '本机修改'),
          changeNote: '本机编辑',
        );
        final localCard = (await repository.getCard(local.id))!;

        await repository.applyVaultMergePlan(
          VaultMergePlan(
            importedBlobs: [importedBlob],
            importedCards: [
              MergedCardRecord(
                card: fixtureCard(
                  'foreign-1',
                  title: '对方独有',
                  revisionNumber: 2,
                ),
                currentOriginals: const ['b1'],
                revisionOriginals: {1: const []},
                appendedRevisions: [
                  MergeRevisionRecord(
                    number: 1,
                    title: '对方独有',
                    content: '对方内容',
                    tags: const ['标签'],
                    status: CardStatus.confirmed,
                    sourceKind: SourceKind.ownerInput,
                    sourceLabel: '本人输入',
                    changeNote: '创建卡片',
                    createdAt: DateTime.utc(2026, 10, 14, 6),
                  ),
                  MergeRevisionRecord(
                    number: 2,
                    title: '对方独有',
                    content: '对方内容二',
                    tags: const ['标签'],
                    status: CardStatus.confirmed,
                    sourceKind: SourceKind.ownerInput,
                    sourceLabel: '本人修改',
                    changeNote: '添加原件引用 · b1.txt',
                    createdAt: DateTime.utc(2026, 10, 14, 7),
                    originalBlobId: 'b1',
                    originalSourceLabel: '本人引用 · b1.txt',
                    originalSourceKind: SourceKind.ownerInput,
                  ),
                ],
              ),
            ],
            updatedCards: [
              MergedCardRecord(
                card: LifeCard(
                  id: localCard.id,
                  title: localCard.title,
                  content: localCard.content,
                  kind: localCard.kind,
                  status: localCard.status,
                  tags: localCard.tags,
                  createdAt: localCard.createdAt,
                  updatedAt: mergedAt,
                  revisionNumber: localCard.revisionNumber + 2,
                ),
                revisionOriginals: {localCard.revisionNumber + 2: const []},
                appendedRevisions: [
                  MergeRevisionRecord(
                    number: localCard.revisionNumber + 1,
                    title: '本机卡片',
                    content: '对方分叉内容',
                    tags: const ['标签'],
                    status: CardStatus.confirmed,
                    sourceKind: SourceKind.ownerInput,
                    sourceLabel: '本人修改',
                    changeNote: '来自另一台设备：更新卡片',
                    createdAt: DateTime.utc(2026, 10, 14, 7, 30),
                  ),
                  MergeRevisionRecord(
                    number: localCard.revisionNumber + 2,
                    title: '本机卡片',
                    content: '本机修改',
                    tags: const ['标签'],
                    status: CardStatus.confirmed,
                    sourceKind: SourceKind.ownerInput,
                    sourceLabel: '合并 · 本机版',
                    changeNote: '合并：暂保留本机版',
                    createdAt: mergedAt,
                  ),
                ],
              ),
            ],
            importedRelations: [
              CardRelation(
                fromCardId: 'foreign-1',
                toCardId: local.id,
                kind: RelationKind.bundleMember,
              ),
            ],
            referenceUnions: [
              MergeCardReferenceUnion(from: local.id, targets: ['foreign-1']),
            ],
            conflicts: [
              CardMergeConflict(
                cardId: local.id,
                mergedAt: mergedAt,
                foreignHead: localCard.revisionNumber + 1,
              ),
            ],
            missingLedgerJson: jsonEncode({
              'blobs/owed.blob': {
                'size': 44,
                'sha256': 'fixture',
                'key': 'AQ',
                'snapshotId': 's1',
              },
            }),
          ),
        );

        // Imports.
        final imported = (await repository.getCard('foreign-1'))!;
        expect(imported.title, '对方独有');
        expect(imported.revisionNumber, 2);
        final importedHistory = await repository.cardHistory('foreign-1');
        expect(importedHistory.map((r) => r.number), [2, 1]);
        expect(importedHistory.first.changeNote, '添加原件引用 · b1.txt');
        final importedSources = await repository.cardSources('foreign-1');
        expect(importedSources.any((s) => s.blobId == 'b1'), isTrue);
        final current = await repository.currentCardSources('foreign-1');
        expect(current.where((s) => s.blobId == 'b1'), hasLength(1));
        expect(await repository.getBlob('b1'), isNotNull);

        // Appends on the common card.
        final history = await repository.cardHistory(local.id);
        expect(history.map((r) => r.number), [4, 3, 2, 1]);
        expect(history.first.changeNote, '合并：暂保留本机版');
        expect(history[1].changeNote, '来自另一台设备：更新卡片');
        final binding = jsonDecode(
          (await repository.readLocalValue('card.originals.${local.id}'))!,
        ) as Map<String, dynamic>;
        expect((binding['revisions'] as Map)['4'], isEmpty);

        // Relations, references, markers and ledger.
        expect(
          (await repository.relationsForCard('foreign-1'))
              .any((r) => r.kind == RelationKind.bundleMember),
          isTrue,
        );
        expect(
          (await repository.cardReferences()).any(
            (r) => r.from == local.id && r.to == 'foreign-1',
          ),
          isTrue,
        );
        final conflicts = CardMergeConflict.decodeAll(
          jsonDecode((await repository.readLocalValue('workbench.merge.v1'))!),
        );
        expect(conflicts[local.id]!.foreignHead, 3);
        expect(
          jsonDecode((await repository.readLocalValue('backup.missing'))!),
          contains('blobs/owed.blob'),
        );
      },
    );

    test('rejects plans that contradict the card table', () async {
      await expectLater(
        repository.applyVaultMergePlan(
          VaultMergePlan(
            updatedCards: [MergedCardRecord(card: fixtureCard('missing'))],
          ),
        ),
        throwsFormatException,
      );
      final card = await repository.createCard(
        const CardDraft(title: '已存在', content: 'fixture'),
      );
      await expectLater(
        repository.applyVaultMergePlan(
          VaultMergePlan(importedCards: [MergedCardRecord(card: card)]),
        ),
        throwsFormatException,
      );
    });
  });

  group('merge markers', () {
    test('read and clear the unresolved marker through the service', () async {
      final repository = MarkerRepository();
      final session = fixtureSession(
        directory: null,
        openRepository: (_, _) async => repository,
      );
      await session.prepare();
      await session.openWithKey(Uint8List(32));
      session.markUnlocked();
      final archive = LifeVaultArchiveService();
      final backup = VaultBackupService(
        session: session,
        archive: archive,
        restoreTransaction: () =>
            throw UnsupportedError('marker fixture: no installation'),
      );
      final merge = VaultMergeService(
        session: session,
        archive: archive,
        backup: backup,
        restoreTransaction: () =>
            throw UnsupportedError('marker fixture: no installation'),
      );
      expect(await merge.mergeConflicts(), isEmpty);
      await repository.writeLocalValue(
        CardMergeConflict.storageKey,
        jsonEncode({
          'version': 1,
          'conflicts': {
            'card-a': CardMergeConflict(
              cardId: 'card-a',
              mergedAt: mergedAt,
              foreignHead: 3,
            ).toJson(),
            'card-b': CardMergeConflict(
              cardId: 'card-b',
              mergedAt: mergedAt,
              foreignDeleted: true,
            ).toJson(),
          },
        }),
      );
      final conflicts = await merge.mergeConflicts();
      expect(conflicts.keys, containsAll(['card-a', 'card-b']));
      expect(conflicts['card-a']!.kind, MergeConflictKind.fork);
      expect(conflicts['card-b']!.kind, MergeConflictKind.foreignDeleted);
      await merge.clearMergeConflict('card-a');
      expect((await merge.mergeConflicts()).keys, ['card-b']);
      await merge.clearMergeConflicts(['card-b']);
      expect(await merge.mergeConflicts(), isEmpty);
      await merge.clearMergeConflict('never-existed');
      session.dispose();
    });
  });
}

class MarkerRepository extends SessionRepository {
  final values = <String, String>{};
  @override
  Future<String?> readLocalValue(String key) async => values[key];
  @override
  Future<void> writeLocalValue(String key, String value) async {
    values[key] = value;
  }
}
