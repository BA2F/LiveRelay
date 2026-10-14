/// B-mode merge (二期「合并导入」) models. The plan is built by
/// `VaultMergeService` from two authenticated repositories and is applied by
/// `VaultRepository.applyVaultMergePlan` in one transaction. Nothing here
/// carries keys, file paths or raw rows.
library;

import 'entities.dart';

/// One revision appended into the merged vault, already in final (merged)
/// numbering. Revision identity is the content fingerprint
/// (`mergeRevisionFingerprint`); numbers are local and may be remapped from
/// the source device.
class MergeRevisionRecord {
  const MergeRevisionRecord({
    required this.number,
    required this.title,
    required this.content,
    required this.tags,
    required this.status,
    required this.sourceKind,
    required this.sourceLabel,
    required this.changeNote,
    required this.createdAt,
    this.originalBlobId,
    this.originalSourceLabel,
    this.originalSourceKind,
  });

  final int number;
  final String title;
  final String content;
  final List<String> tags;
  final CardStatus status;
  final SourceKind sourceKind;
  final String sourceLabel;
  final String changeNote;
  final DateTime createdAt;

  /// The original added by this revision, when the merge could tell. The
  /// attached source row carries this blob so the record stays visible in
  /// `cardSources` / `currentCardSources`.
  final String? originalBlobId;
  final String? originalSourceLabel;
  final SourceKind? originalSourceKind;
}

/// One card the merge writes.
///
/// In [VaultMergePlan.importedCards] the revisions are the card's whole chain
/// (numbers as on the source device). In [VaultMergePlan.updatedCards] they
/// continue the existing local chain, and the card row is replaced by
/// [card] (projection kept deliberately local for a fork).
class MergedCardRecord {
  const MergedCardRecord({
    required this.card,
    this.appendedRevisions = const [],
    this.currentOriginals,
    this.revisionOriginals = const {},
  });

  final LifeCard card;
  final List<MergeRevisionRecord> appendedRevisions;

  /// Binding `card.originals.<id>.current` after the merge. Null keeps the
  /// existing value (or absence) — used for the fork/reaffirm case where the
  /// local projection stays current.
  final List<String>? currentOriginals;

  /// `card.originals.<id>.revisions` entries to write, keyed by final
  /// revision number. Empty lists are meaningful ("as of this revision the
  /// card had no originals") and are written as-is.
  final Map<int, List<String>> revisionOriginals;
}

class MergeCardReferenceUnion {
  const MergeCardReferenceUnion({required this.from, required this.targets});

  final String from;
  final List<String> targets;
}

/// How an unresolved merge conflict is displayed; also drives the resolution
/// action. `fork` resolves through `restoreCardRevision(foreignHead)`,
/// `foreignDeleted` through trashing the card, `localDeleted` through
/// restoring the card and then restoring `foreignHead`.
enum MergeConflictKind { fork, foreignDeleted, localDeleted }

/// One entry of the `workbench.merge.v1` unresolved marker.
class CardMergeConflict {
  const CardMergeConflict({
    required this.cardId,
    required this.mergedAt,
    this.foreignHead,
    this.foreignDeleted = false,
    this.localDeleted = false,
  });

  static const storageKey = 'workbench.merge.v1';
  static const version = 1;

  final String cardId;
  final DateTime mergedAt;

  /// Final (merged) revision number of the other device's head. Null when
  /// the other device deleted the card instead of extending it.
  final int? foreignHead;

  /// The other device deleted this card; the local version was kept.
  final bool foreignDeleted;

  /// This device deleted the card while the other device changed it.
  final bool localDeleted;

  MergeConflictKind get kind => foreignDeleted
      ? MergeConflictKind.foreignDeleted
      : localDeleted
      ? MergeConflictKind.localDeleted
      : MergeConflictKind.fork;

  Map<String, Object?> toJson() => <String, Object?>{
    'foreignHead': foreignHead,
    if (foreignDeleted) 'foreignDeleted': true,
    if (localDeleted) 'localDeleted': true,
    'mergedAt': mergedAt.toUtc().toIso8601String(),
  };

  static CardMergeConflict? tryDecode(String cardId, Object? raw) {
    if (raw is! Map) return null;
    final mergedAt = raw['mergedAt'];
    if (mergedAt is! String) return null;
    final parsed = DateTime.tryParse(mergedAt);
    if (parsed == null) return null;
    final head = raw['foreignHead'];
    return CardMergeConflict(
      cardId: cardId,
      foreignHead: head is int ? head : null,
      foreignDeleted: raw['foreignDeleted'] == true,
      localDeleted: raw['localDeleted'] == true,
      mergedAt: parsed.toUtc(),
    );
  }

  static Map<String, CardMergeConflict> decodeAll(Object? decoded) {
    if (decoded is! Map || decoded['version'] != version) return const {};
    final raw = decoded['conflicts'];
    if (raw is! Map) return const {};
    final result = <String, CardMergeConflict>{};
    for (final entry in raw.entries) {
      if (entry.key is! String) continue;
      final conflict = tryDecode(entry.key as String, entry.value);
      if (conflict != null) result[conflict.cardId] = conflict;
    }
    return result;
  }
}

/// The complete set of writes that installs a merged vault. Applied atomically;
/// the caller has already authenticated both sides and built every record.
class VaultMergePlan {
  const VaultMergePlan({
    this.importedCards = const [],
    this.updatedCards = const [],
    this.importedBlobs = const [],
    this.importedRelations = const [],
    this.referenceUnions = const [],
    this.conflicts = const [],
    this.missingLedgerJson,
  });

  /// Cards that exist only on the other device; inserted with their chain.
  final List<MergedCardRecord> importedCards;

  /// Cards present on both sides whose row and/or chain changes.
  final List<MergedCardRecord> updatedCards;

  /// Blob rows the local vault does not have yet.
  final List<VaultBlob> importedBlobs;

  /// Card relations (`splitFrom` / `bundleMember`) missing locally.
  final List<CardRelation> importedRelations;

  /// Unioned workbench references per card (full replacement sets).
  final List<MergeCardReferenceUnion> referenceUnions;

  /// Unresolved markers to record in `workbench.merge.v1`; entries for the
  /// same card replace older ones.
  final List<CardMergeConflict> conflicts;

  /// Fully merged `backup.missing` ledger; null leaves the local value as-is.
  final String? missingLedgerJson;
}
