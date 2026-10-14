/// Pure B-mode card merge: both revision chains in, one decision out.
///
/// The two devices share a vault lineage, so a card's chain is compared by
/// `(number, fingerprint)` to find the common prefix (W1 口径). Nothing here
/// touches a database, a key or a file; the service layer feeds authenticated
/// facts and applies the result through `VaultRepository.applyVaultMergePlan`.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';

import '../../core/domain/entities.dart';
import '../../core/domain/vault_merge.dart';

/// 一期修订身份：内容指纹。稳定身份并入 K3 后替换此处定义。
String mergeRevisionFingerprintInput(CardRevision revision) => [
  revision.title,
  revision.content,
  jsonEncode(revision.tags),
  revision.status.name,
  revision.sourceKind.name,
  revision.sourceLabel,
  revision.createdAt.toUtc().toIso8601String(),
].join('|');

Future<String> mergeRevisionFingerprint(CardRevision revision) async {
  final digest = await Sha256().hash(
    utf8.encode(mergeRevisionFingerprintInput(revision)),
  );
  return base64UrlEncode(digest.bytes);
}

/// Length of the pairwise `(number, fingerprint)` common prefix.
Future<int> commonRevisionPrefix(
  List<CardRevision> local,
  List<CardRevision> foreign,
) async {
  final limit = math.min(local.length, foreign.length);
  var length = 0;
  while (length < limit) {
    final a = local[length], b = foreign[length];
    if (a.number != b.number) break;
    if (await mergeRevisionFingerprint(a) !=
        await mergeRevisionFingerprint(b)) {
      break;
    }
    length++;
  }
  return length;
}

/// One side's facts for one card. `card` is null when that vault does not
/// have the card at all; `revisions` are ascending; `currentOriginals` and
/// `originalSnapshots` describe the `card.originals.<id>` binding (the
/// service synthesizes the current set from source rows when no binding
/// exists).
class CardMergeSide {
  const CardMergeSide({
    this.card,
    this.revisions = const [],
    this.currentOriginals = const [],
    this.originalSnapshots = const {},
    this.originalLabels = const {},
  });

  final LifeCard? card;
  final List<CardRevision> revisions;
  final List<String> currentOriginals;
  final Map<int, List<String>> originalSnapshots;

  /// Original blob id -> the source row label/kind that carried it; used to
  /// keep merged source rows faithful to this side.
  final Map<String, ({String label, SourceKind kind})> originalLabels;
}

enum CardMergeAction {
  /// Nothing to write: both sides agree, or this device has the only copy.
  unchanged,

  /// The card exists only on the other device and is brought in.
  importCard,

  /// Single-sided extension: append the other device's suffix.
  fastForward,

  /// Both sides diverged: append the other segment plus a local reaffirm and
  /// record an unresolved marker.
  fork,

  /// The other device deleted an unchanged card: the deletion is adopted.
  adoptDeletion,

  /// Keep the local version and record an unresolved marker.
  keepLocal,
}

class CardMergeDecision {
  const CardMergeDecision({required this.action, this.record, this.conflict});

  final CardMergeAction action;

  /// Row + revisions to write; null leaves the card untouched.
  final MergedCardRecord? record;

  /// Unresolved marker; null when the merge result is settled.
  final CardMergeConflict? conflict;
}

const String _foreignChangePrefix = '来自另一台设备：';
const String _reaffirmNote = '合并：暂保留本机版';
const String _reaffirmSourceLabel = '合并 · 本机版';

Future<CardMergeDecision> planCardMerge({
  required CardMergeSide local,
  required CardMergeSide foreign,
  required DateTime mergedAt,
}) async {
  final localCard = local.card, foreignCard = foreign.card;
  if (localCard == null && foreignCard == null) {
    return const CardMergeDecision(action: CardMergeAction.unchanged);
  }
  if (localCard == null) {
    // 对方回收区里的历史卡片不再引入本机。
    if (foreignCard!.isDeleted) {
      return const CardMergeDecision(action: CardMergeAction.unchanged);
    }
    return CardMergeDecision(
      action: CardMergeAction.importCard,
      record: _importRecord(foreign),
    );
  }
  if (foreignCard == null) {
    // 本机独有的卡片：本机版优先。
    return const CardMergeDecision(action: CardMergeAction.unchanged);
  }
  if (local.revisions.isEmpty || foreign.revisions.isEmpty) {
    // 卡片行与修订在仓库里同事务写入；缺链说明数据库已损坏。
    throw StateError('卡片修订链为空，无法合并');
  }
  if (localCard.isDeleted && foreignCard.isDeleted) {
    return const CardMergeDecision(action: CardMergeAction.unchanged);
  }
  final prefix = await commonRevisionPrefix(local.revisions, foreign.revisions);
  if (!localCard.isDeleted && !foreignCard.isDeleted) {
    if (prefix == local.revisions.length &&
        prefix == foreign.revisions.length) {
      return const CardMergeDecision(action: CardMergeAction.unchanged);
    }
    if (prefix == foreign.revisions.length) {
      // 本机领先：对方没有新内容。
      return const CardMergeDecision(action: CardMergeAction.unchanged);
    }
    if (prefix == local.revisions.length) {
      return CardMergeDecision(
        action: CardMergeAction.fastForward,
        record: _fastForwardRecord(local, foreign, prefix, mergedAt),
      );
    }
    return _forkDecision(
      local,
      foreign,
      prefix: prefix,
      mergedAt: mergedAt,
      keepDeleted: false,
    );
  }
  if (!foreignCard.isDeleted) {
    // 本机已删除。对方无新内容时删除保持；对方有修改时保持本机删除，
    // 但把对方分叉段续进回收历史并记未解决标记，供恢复后采用。
    if (prefix == foreign.revisions.length) {
      return const CardMergeDecision(action: CardMergeAction.unchanged);
    }
    return _forkDecision(
      local,
      foreign,
      prefix: prefix,
      mergedAt: mergedAt,
      keepDeleted: true,
    );
  }
  // 对方已删除。
  if (prefix == local.revisions.length) {
    // 对方删除且本机未改动：采用删除。
    return CardMergeDecision(
      action: CardMergeAction.adoptDeletion,
      record: MergedCardRecord(
        card: _copyCard(localCard, updatedAt: mergedAt, deletedAt: mergedAt),
      ),
    );
  }
  // 对方删除且本机有改动：本机版优先＋标记。
  return CardMergeDecision(
    action: CardMergeAction.keepLocal,
    conflict: CardMergeConflict(
      cardId: localCard.id,
      mergedAt: mergedAt,
      foreignDeleted: true,
    ),
  );
}

MergedCardRecord _importRecord(CardMergeSide foreign) {
  final card = foreign.card!;
  final appended = <MergeRevisionRecord>[];
  for (var i = 0; i < foreign.revisions.length; i++) {
    final revision = foreign.revisions[i];
    appended.add(
      _recordFor(
        revision,
        number: revision.number,
        changeNote: revision.changeNote,
        added: _addedAt(foreign, i),
        labels: foreign.originalLabels,
      ),
    );
  }
  return MergedCardRecord(
    card: card,
    appendedRevisions: appended,
    currentOriginals: List.of(foreign.currentOriginals),
    // 只搬对方真实存在的逐修订快照；没有绑定的卡片由其来源行还原原件集。
    revisionOriginals: {
      for (final entry in foreign.originalSnapshots.entries)
        entry.key: List.of(entry.value),
    },
  );
}

/// Single-sided extension: append the other side's suffix with continued
/// numbering and adopt the other head as the projection.
MergedCardRecord _fastForwardRecord(
  CardMergeSide local,
  CardMergeSide foreign,
  int prefix,
  DateTime mergedAt,
) {
  final localHead = local.revisions.last;
  final foreignHead = foreign.revisions.last;
  final appended = <MergeRevisionRecord>[];
  final snapshots = <int, List<String>>{};
  var number = localHead.number;
  for (var i = prefix; i < foreign.revisions.length; i++) {
    number++;
    final revision = foreign.revisions[i];
    snapshots[number] = _asOf(foreign, i);
    appended.add(
      _recordFor(
        revision,
        number: number,
        changeNote: revision.changeNote,
        added: _addedAt(foreign, i),
        labels: foreign.originalLabels,
      ),
    );
  }
  final foreignCard = foreign.card!;
  final row = LifeCard(
    id: foreignCard.id,
    title: foreignHead.title,
    content: foreignHead.content,
    kind: foreignCard.kind,
    status: foreignHead.status,
    tags: List.of(foreignHead.tags),
    createdAt: foreignCard.createdAt,
    updatedAt: mergedAt,
    confirmedAt: foreignCard.confirmedAt,
    parentCardId: foreignCard.parentCardId,
    revisionNumber: number,
  );
  return MergedCardRecord(
    card: row,
    appendedRevisions: appended,
    currentOriginals: List.of(_asOf(foreign, foreign.revisions.length - 1)),
    revisionOriginals: snapshots,
  );
}

/// Both sides diverged (or the local deletion meets foreign changes): append
/// the other segment, then a reaffirm revision equal to the local head.
CardMergeDecision _forkDecision(
  CardMergeSide local,
  CardMergeSide foreign, {
  required int prefix,
  required DateTime mergedAt,
  required bool keepDeleted,
}) {
  final localCard = local.card!;
  final localHead = local.revisions.last;
  final appended = <MergeRevisionRecord>[];
  final snapshots = <int, List<String>>{};
  var number = localHead.number;
  for (var i = prefix; i < foreign.revisions.length; i++) {
    number++;
    final revision = foreign.revisions[i];
    snapshots[number] = _asOf(foreign, i);
    appended.add(
      _recordFor(
        revision,
        number: number,
        changeNote: '$_foreignChangePrefix${revision.changeNote}',
        added: _addedAt(foreign, i),
        labels: foreign.originalLabels,
      ),
    );
  }
  final foreignHeadNumber = number;
  number++;
  snapshots[number] = _asOf(local, local.revisions.length - 1);
  appended.add(
    MergeRevisionRecord(
      number: number,
      title: localHead.title,
      content: localHead.content,
      tags: List.of(localHead.tags),
      status: localHead.status,
      sourceKind: SourceKind.ownerInput,
      sourceLabel: _reaffirmSourceLabel,
      changeNote: _reaffirmNote,
      createdAt: mergedAt,
    ),
  );
  return CardMergeDecision(
    action: CardMergeAction.fork,
    record: MergedCardRecord(
      card: _copyCard(
        localCard,
        updatedAt: mergedAt,
        revisionNumber: number,
        deletedAt: keepDeleted ? localCard.deletedAt : null,
      ),
      appendedRevisions: appended,
      revisionOriginals: snapshots,
    ),
    conflict: CardMergeConflict(
      cardId: localCard.id,
      mergedAt: mergedAt,
      foreignHead: foreignHeadNumber,
      localDeleted: keepDeleted,
    ),
  );
}

/// The originals set recorded "as of" the revision at [index]; unknown
/// snapshots fall back to the current set.
List<String> _asOf(CardMergeSide side, int index) =>
    side.originalSnapshots[side.revisions[index].number] ??
    side.currentOriginals;

/// Blobs the revision at [index] added relative to the previous revision.
List<String> _addedAt(CardMergeSide side, int index) {
  final current = _asOf(side, index);
  if (index == 0) return List.of(current);
  final previous = _asOf(side, index - 1).toSet();
  return [
    for (final blobId in current)
      if (!previous.contains(blobId)) blobId,
  ];
}

MergeRevisionRecord _recordFor(
  CardRevision revision, {
  required int number,
  required String changeNote,
  required List<String> added,
  required Map<String, ({String label, SourceKind kind})> labels,
}) {
  final primary = added.isEmpty ? null : added.last;
  final label = primary == null ? null : labels[primary];
  return MergeRevisionRecord(
    number: number,
    title: revision.title,
    content: revision.content,
    tags: List.of(revision.tags),
    status: revision.status,
    sourceKind: revision.sourceKind,
    sourceLabel: revision.sourceLabel,
    changeNote: changeNote,
    createdAt: revision.createdAt,
    originalBlobId: primary,
    originalSourceLabel: primary == null
        ? null
        : (label?.label ?? revision.sourceLabel),
    originalSourceKind: primary == null
        ? null
        : (label?.kind ?? revision.sourceKind),
  );
}

LifeCard _copyCard(
  LifeCard card, {
  required DateTime updatedAt,
  DateTime? deletedAt,
  int? revisionNumber,
}) => LifeCard(
  id: card.id,
  title: card.title,
  content: card.content,
  kind: card.kind,
  status: card.status,
  tags: List.of(card.tags),
  createdAt: card.createdAt,
  updatedAt: updatedAt,
  confirmedAt: card.confirmedAt,
  deletedAt: deletedAt,
  parentCardId: card.parentCardId,
  revisionNumber: revisionNumber ?? card.revisionNumber,
);
