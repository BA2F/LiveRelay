import 'dart:typed_data';

import '../domain/entities.dart';
import '../domain/card_references.dart';
import '../domain/vault_merge.dart';
import '../ai/review_source.dart';
import '../ai/review_actions.dart';

abstract interface class VaultRepository {
  Future<String?> readChunkedLocalValue(String key);
  Future<void> writeChunkedLocalValue(String key, String value);
  Future<Uint8List> exportLocalState();
  Future<void> importLocalState(Uint8List bytes);
  Future<String?> readLocalValue(String key);
  Future<void> writeLocalValue(String key, String value);

  /// All values commit together, including challenge consumption and binding.
  Future<void> writeLocalValues(Map<String, String> values);
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
    bool recycled = false,
  });

  Future<LifeCard?> getCard(String id);
  Future<List<CardReference>> cardReferences();
  Future<void> setCardReferences(String from, List<String> targets);

  Future<List<CardRevision>> cardHistory(String cardId);

  Future<LifeCard> createCard(
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String sourceLabel = '本人输入',
  });

  Future<LifeCard> updateCard(
    String id,
    CardDraft draft, {
    String changeNote = '更新卡片',
  });

  Future<LifeCard> confirmCard(String id);

  Future<List<LifeCard>> splitCard(String id, List<CardDraft> parts);

  Future<LifeCard> combineCards(String title, List<String> memberIds);

  Future<List<CardRelation>> relationsForCard(String cardId);

  Future<void> trashCard(String id);
  Future<CardDeletionPreview> previewCardDeletion(List<String> ids);
  Future<void> trashCards(
    List<String> ids, {
    bool recycleUnsharedOriginals = false,
  });
  Future<List<String>> recycledOriginalIds();
  Future<void> restoreOriginal(String id);
  Future<void> restoreCard(String id);
  Future<List<CardSource>> cardSources(String id);
  Future<List<CardSource>> currentCardSources(String id);
  Future<void> setCardOriginals(String id, List<String> blobIds);
  Future<LifeCard> restoreCardRevision(String id, int number);
  Future<List<LifeCard>> cardsForBlob(String blobId);
  Future<LifeCard> createCardFromOriginal(
    String blobId,
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String? sourceLabel,
  });
  Future<DateTime?> lastBackupExport();
  Future<void> recordBackupExport(DateTime time);

  Future<List<VaultBlob>> listBlobs();
  Future<VaultBlob?> getBlob(String id);

  /// Registers one encrypted original row (with its audit entry) without
  /// creating any card. The caller decides how the original is referenced,
  /// for example through [setCardOriginals].
  Future<void> registerBlobRow(VaultBlob blob);

  /// Registers the original row and creates the import source card that
  /// references it.
  Future<LifeCard> registerBlob(VaultBlob blob);

  Future<void> updateBlobOcr(String id, String text);

  Future<LifeCard> saveOcrResult(String blobId, OcrResult result);

  Future<void> saveSensitiveMarks(String blobId, List<SensitiveMark> marks);

  Future<List<LifeCard>> saveAiSuggestions(
    String blobId,
    List<CardDraft> drafts, {
    required String providerLabel,
  });

  Future<List<LifeCard>> saveAgentSuggestions(
    String sourceText,
    List<CardDraft> drafts, {
    required String providerLabel,
  });

  /// Idempotent explicit review. Only explicit owner plans change release policy.
  Future<List<LifeCard>> saveReviewedAgentSuggestions(
    String reviewId,
    String sourceText,
    List<CardDraft> drafts, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  });

  Future<ReviewSource?> cardReviewSource(String cardId);

  Future<List<CredentialEntry>> listCredentials({
    String query = '',
    bool recycled = false,
  });

  Future<CredentialEntry> saveCredential(CredentialDraft draft, {String? id});

  Future<int> importCredentials(List<CredentialDraft> drafts);

  Future<List<CredentialRevision>> credentialHistory(String id);

  Future<void> trashCredential(String id);
  Future<void> restoreCredential(String id);

  Future<void> purgeCredential(String id);

  Future<ReleasePolicy> getReleasePolicy(String recordType, String recordId);

  Future<List<ReleasePolicy>> listReleasePolicies();

  Future<void> saveReleasePolicy(ReleasePolicy policy);

  Future<LifeState> currentLifeState();

  Future<List<LifeStateEvent>> lifeStateHistory();

  Future<void> transitionLifeState(LifeState to, {required String reason});

  Future<void> resetLifeStateSimulation({required String reason});

  Future<VaultInsights> insights();

  /// Applies one B-mode merge plan in a single transaction. The caller has
  /// already authenticated both vault copies and built every record; this
  /// method only writes (card rows, revisions with their source rows, the
  /// originals binding, blob rows, relations, reference unions, unresolved
  /// markers and the owed-originals ledger).
  Future<void> applyVaultMergePlan(VaultMergePlan plan);

  Future<void> close();
}
