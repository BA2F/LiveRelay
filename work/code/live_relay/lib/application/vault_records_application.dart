import 'dart:typed_data';

import '../core/ai/review_source.dart';
import '../core/domain/card_mutations.dart';
import '../core/domain/entities.dart';
import '../core/ports/vault_lifecycle.dart';
import '../core/ports/vault_repository.dart';
import 'import/edge_password_csv_importer.dart';
import 'vault_content_service.dart';
import 'vault_snapshot_query.dart';

/// Typed commands/queries shared by front ends. The session owns the write gate;
/// repositories own atomic facts/rules/persistence; presentation owns UI errors.
class VaultRecordsApplication {
  const VaultRecordsApplication({
    required this.vault,
    required this.content,
    required this.snapshots,
    this.clock = DateTime.now,
  });
  final VaultLifecycle vault;
  final VaultContentService content;
  final VaultSnapshotQuery snapshots;
  final DateTime Function() clock;
  VaultRepository get _repository {
    if (!vault.isUnlocked) throw StateError('请先解锁资料库');
    if (vault.isMaintaining) throw StateError('资料库维护正在进行');
    return vault.repository;
  }

  void _current(int generation) {
    if (!vault.isUnlocked || generation != vault.sessionGeneration) {
      throw StateError('资料库已关闭或重开，本次操作已丢弃');
    }
  }

  Future<T> _read<T>(Future<T> Function(VaultRepository r) operation) async {
    final generation = vault.sessionGeneration;
    final result = await operation(_repository);
    _current(generation);
    return result;
  }

  Future<T> _write<T>(Future<T> Function(VaultRepository r) operation) =>
      vault.runMutation(() async {
        final generation = vault.sessionGeneration;
        final result = await operation(_repository);
        _current(generation);
        await snapshots.load();
        return result;
      });
  Future<LifeCard> createCard(
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String sourceLabel = '本人输入',
  }) {
    final input = DraftRules.freeze(draft);
    return _write(
      (r) =>
          r.createCard(input, sourceKind: sourceKind, sourceLabel: sourceLabel),
    );
  }

  Future<LifeCard> updateCard(
    String id,
    CardDraft draft, {
    String changeNote = '更新卡片',
  }) {
    final input = DraftRules.freeze(draft);
    return _write((r) => r.updateCard(id, input, changeNote: changeNote));
  }

  Future<LifeCard> confirmCard(String id) => _write((r) => r.confirmCard(id));
  Future<List<LifeCard>> splitCard(String id, List<CardDraft> drafts) {
    final input = List<CardDraft>.unmodifiable(drafts.map(DraftRules.freeze));
    return _write((r) => r.splitCard(id, input));
  }

  Future<LifeCard> combineCards(String title, List<String> members) {
    final input = List<String>.unmodifiable(members);
    return _write((r) => r.combineCards(title, input));
  }

  Future<void> setCardReferences(String from, List<String> targets) {
    final input = List<String>.unmodifiable(targets);
    return _write((r) => r.setCardReferences(from, input));
  }

  Future<void> setCardOriginals(String id, List<String> originals) {
    final input = List<String>.unmodifiable(originals);
    return _write((r) => r.setCardOriginals(id, input));
  }

  /// 把一个新附件写入加密原件并直接关联到既有卡片，不创建来源卡片。
  /// 文件补偿由内容层负责；引用更新失败时只会留下一个未关联的原件，
  /// 可在卡片的原件引用里重新勾选。
  Future<LifeCard> attachOriginalToCard(
    String cardId, {
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) => _write((r) async {
    final existing = await r.getCard(cardId);
    if (existing == null || existing.isDeleted) {
      throw const FormatException('卡片不存在');
    }
    final blob = await content.writeOriginalOnly(
      bytes: bytes,
      originalName: originalName,
      mimeType: mimeType,
      mediaKind: mediaKind,
    );
    final sources = await r.currentCardSources(cardId);
    final ids = [
      for (final source in sources)
        if (source.blobId != null) source.blobId!,
      blob.id,
    ];
    await r.setCardOriginals(cardId, ids);
    final card = await r.getCard(cardId);
    if (card == null) throw const FormatException('卡片不存在');
    return card;
  }).whenComplete(() => bytes.fillRange(0, bytes.length, 0));

  Future<LifeCard> restoreCardRevision(String id, int number) =>
      _write((r) => r.restoreCardRevision(id, number));
  Future<void> trashCard(String id) => _write((r) => r.trashCard(id));
  Future<void> restoreCard(String id) => _write((r) => r.restoreCard(id));
  Future<void> trashCards(
    List<String> ids, {
    bool recycleUnsharedOriginals = false,
  }) {
    final input = List<String>.unmodifiable(ids);
    return _write(
      (r) => r.trashCards(
        input,
        recycleUnsharedOriginals: recycleUnsharedOriginals,
      ),
    );
  }

  Future<void> restoreOriginal(String id) =>
      _write((r) => r.restoreOriginal(id));
  Future<LifeCard> createCardFromOriginal(String id, CardDraft draft) {
    final input = DraftRules.freeze(draft);
    return _write((r) => r.createCardFromOriginal(id, input));
  }

  Future<CredentialEntry> saveCredential(CredentialDraft draft, {String? id}) {
    final input = CredentialDraft(
      title: draft.title,
      username: draft.username,
      secret: draft.secret,
      website: draft.website,
      notes: draft.notes,
      tags: List.unmodifiable(draft.tags),
    );
    return _write((r) => r.saveCredential(input, id: id));
  }

  Future<void> trashCredential(String id) =>
      _write((r) => r.trashCredential(id));
  Future<void> restoreCredential(String id) =>
      _write((r) => r.restoreCredential(id));
  Future<void> purgeCredential(String id) =>
      _write((r) => r.purgeCredential(id));
  Future<void> saveReleasePolicy(ReleasePolicy policy) =>
      _write((r) => r.saveReleasePolicy(policy));
  Future<void> transitionLifeState(LifeState to, {required String reason}) =>
      _write((r) => r.transitionLifeState(to, reason: reason));
  Future<void> resetLifeStateSimulation({required String reason}) =>
      _write((r) => r.resetLifeStateSimulation(reason: reason));
  Future<void> markBackupExported() =>
      _write((r) => r.recordBackupExport(clock()));
  Future<void> saveSensitiveMarks(String id, List<SensitiveMark> marks) {
    final input = List<SensitiveMark>.unmodifiable(marks);
    return _write((r) => r.saveSensitiveMarks(id, input));
  }

  Future<LifeCard> importOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) => _write(
    (_) => content.importOriginal(
      bytes: bytes,
      originalName: originalName,
      mimeType: mimeType,
      mediaKind: mediaKind,
    ),
  ).whenComplete(() => bytes.fillRange(0, bytes.length, 0));
  Future<LifeCard> runOcr(String id) => _write((_) => content.runOcr(id));
  Future<EdgePasswordImportResult> importEdgePasswords(Uint8List bytes) =>
      _write((_) => content.importEdgePasswords(bytes))
          .whenComplete(() => bytes.fillRange(0, bytes.length, 0));
  Future<LifeCard> saveSpeechDraft(String text, {String? blobId}) =>
      _write((_) => content.saveSpeechDraft(text, blobId: blobId));
  Future<Uint8List> readOriginal(String id) async {
    _repository;
    return content.readOriginal(id);
  }
  Future<LifeCard?> getCard(String id) => _read((r) => r.getCard(id));
  Future<List<LifeCard>> cardsForBlob(String id) =>
      _read((r) => r.cardsForBlob(id));
  Future<List<CardSource>> cardSources(String id) =>
      _read((r) => r.cardSources(id));
  Future<List<CardSource>> currentCardSources(String id) =>
      _read((r) => r.currentCardSources(id));
  Future<List<CardRevision>> cardHistory(String id) =>
      _read((r) => r.cardHistory(id));
  Future<ReviewSource?> cardReviewSource(String id) =>
      _read((r) => r.cardReviewSource(id));
  Future<List<CardRelation>> cardRelations(String id) =>
      _read((r) => r.relationsForCard(id));
  Future<CardDeletionPreview> previewCardDeletion(List<String> ids) =>
      _read((r) => r.previewCardDeletion(List.unmodifiable(ids)));
  Future<List<CredentialRevision>> credentialHistory(String id) =>
      _read((r) => r.credentialHistory(id));
  Future<ReleasePolicy> releasePolicy(String type, String id) =>
      _read((r) => r.getReleasePolicy(type, id));
}
