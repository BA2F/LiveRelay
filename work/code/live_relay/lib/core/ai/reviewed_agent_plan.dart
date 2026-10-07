import '../domain/entities.dart';
import 'review_actions.dart';
import 'review_source.dart';

/// Business rules for an explicit confirmation. Storage reads targets inside
/// its transaction and passes those current facts here before writing anything.
class ReviewedAgentPlan {
  ReviewedAgentPlan({
    required this.reviewId,
    required this.sourceText,
    required List<CardDraft> drafts,
    required this.providerLabel,
    this.reviewSource,
    List<ReviewActions> actions = const [],
  }) : drafts = List.unmodifiable([
         for (final draft in drafts)
           CardDraft(
             title: draft.title,
             content: draft.content,
             kind: draft.kind,
             status: draft.status,
             tags: List.unmodifiable(draft.tags),
           ),
       ]),
       actions = List.unmodifiable([
         for (final action in actions)
           ReviewActions(
             bundleId: action.bundleId,
             referenceIds: List.unmodifiable(action.referenceIds),
             incapacitated: action.incapacitated,
             deceased: action.deceased,
           ),
       ]) {
    if (!RegExp(r'^[a-zA-Z0-9-]{1,64}$').hasMatch(reviewId) ||
        (sourceText.length > 32000 && reviewSource == null) ||
        drafts.isEmpty ||
        drafts.length > 20 ||
        (actions.isNotEmpty && actions.length != drafts.length) ||
        (reviewSource != null &&
            (reviewSource!.reviewId != reviewId ||
                reviewSource!.providerLabel != providerLabel))) {
      throw const FormatException('确认建议数量或来源大小错误');
    }
    evidence = reviewSource?.withActions(this.actions).encode();
  }
  final String reviewId, sourceText, providerLabel;
  final List<CardDraft> drafts;
  final ReviewSource? reviewSource;
  final List<ReviewActions> actions;
  late final String? evidence;
  String get receiptKey => 'agent.review.$reviewId';
  String get planKey => 'agent.plan.$reviewId';
  String get legacySource => sourceText.length <= 32000
      ? sourceText
      : '完整输入和附件已保存在独立确认来源记录 $reviewId；输入共${sourceText.length}字。';
  Set<String> get targetIds => {
    for (final action in actions) ...[
      if (action.bundleId != null) action.bundleId!,
      ...action.referenceIds,
    ],
  };

  void validateTargets(Map<String, LifeCard?> targets) {
    for (final action in actions) {
      action.validate();
      if (action.bundleId != null) {
        final bundle = targets[action.bundleId];
        if (bundle == null ||
            bundle.isDeleted ||
            bundle.kind != CardKind.bundle) {
          throw const FormatException('所选收纳组合已失效，请重新选择');
        }
      }
      for (final id in action.referenceIds) {
        final card = targets[id];
        if (card == null || card.isDeleted) {
          throw const FormatException('所选引用卡片已失效，请重新选择');
        }
      }
    }
  }
}
