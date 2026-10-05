import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

void main() {
  test('source linking, unlinking and revision restore retain immutable provenance', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      await r.registerBlob(
        VaultBlob(
          id: 'blob-fixture',
          originalName: 'fixture.txt',
          mediaKind: BlobMediaKind.document,
          mimeType: 'text/plain',
          relativePath: 'blobs/fixture',
          byteLength: 20,
          sha256: 'fixture',
          createdAt: DateTime.utc(2026),
        ),
      );
      final card = await r.createCard(
        const CardDraft(title: '摘要', content: '虚构摘要', status: CardStatus.draft),
      );
      await r.setCardOriginals(card.id, ['blob-fixture']);
      expect(
        (await r.currentCardSources(card.id))
            .any((s) => s.blobId == 'blob-fixture'),
        isTrue,
      );
      await r.setCardOriginals(card.id, []);
      expect(
        (await r.currentCardSources(card.id)).any((s) => s.blobId != null),
        isFalse,
      );
      expect(
        (await r.cardSources(card.id)).any((s) => s.blobId == 'blob-fixture'),
        isTrue,
      );
      final restored = await r.restoreCardRevision(card.id, 2);
      expect(restored.revisionNumber, 4);
      expect(restored.status, CardStatus.draft);
      expect(
        (await r.currentCardSources(card.id))
            .any((s) => s.blobId == 'blob-fixture'),
        isTrue,
      );
      await expectLater(
        r.setCardOriginals(card.id, ['missing']),
        throwsFormatException,
      );
      expect((await r.getCard(card.id))!.revisionNumber, 4);
    } finally {
      await r.close();
    }
  });
  test('optional original recycle protects shared history including recycled cards and restores atomically', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      final original = await r.registerBlob(
        VaultBlob(
          id: 'blob-fixture',
          originalName: 'fixture.txt',
          mediaKind: BlobMediaKind.document,
          mimeType: 'text/plain',
          relativePath: 'blobs/fixture',
          byteLength: 20,
          sha256: 'fixture',
          createdAt: DateTime.utc(2026),
        ),
      );
      final other = await r.createCard(
        const CardDraft(title: '共享摘要', content: '虚构摘要'),
      );
      await r.setCardOriginals(other.id, ['blob-fixture']);
      await r.setCardOriginals(other.id, []);
      final preview = await r.previewCardDeletion([original.id]);
      expect(preview.recyclableOriginals, isEmpty);
      expect(preview.protectedOriginals.single.id, 'blob-fixture');
      await r.trashCard(other.id);
      expect(
        (await r.previewCardDeletion([original.id])).protectedOriginals,
        hasLength(1),
      );
      await r.restoreCard(other.id);
      await r.trashCards([
        original.id,
        other.id,
      ], recycleUnsharedOriginals: true);
      expect(await r.recycledOriginalIds(), ['blob-fixture']);
      expect(await r.listBlobs(), hasLength(1));
      await r.restoreCard(other.id);
      expect(await r.recycledOriginalIds(), isEmpty);
      expect(await r.cardHistory(other.id), hasLength(3));
      await expectLater(
        r.trashCards([other.id, 'missing'], recycleUnsharedOriginals: true),
        throwsFormatException,
      );
      expect((await r.getCard(other.id))!.isDeleted, isFalse);
    } finally {
      await r.close();
    }
  });
}
