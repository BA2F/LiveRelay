import 'dart:convert';

import '../../core/ai/ai_privacy.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/review_source.dart';
import '../../core/domain/entities.dart';
import '../../core/ports/unlocked_vault.dart';
import '../draft_agent_service.dart';

/// Explicit owner confirmation. The repository operation commits cards,
/// sources, plans and receipt atomically; this service never splits that write.
class AgentReviewService {
  const AgentReviewService(this.vault);
  final UnlockedVault vault;

  Future<List<LifeCard>> accept(
    String reviewId,
    String sourceText,
    List<AiCardSuggestion> suggestions, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  }) => vault.repository.saveReviewedAgentSuggestions(
    reviewId,
    sourceText,
    suggestions
        .map(
          (s) => CardDraft(
            title: s.title,
            content: s.content,
            kind: s.kind,
            status: CardStatus.confirmed,
            tags: ['AI', if (s.isInference) '推断', ...s.tags],
          ),
        )
        .toList(growable: false),
    providerLabel: providerLabel,
    originalIds: originalIds,
    reviewSource: reviewSource,
    actions: actions,
  );

  Future<List<LifeCard>> saveDrafts(AgentDraftBatch batch) =>
      vault.repository.saveAgentSuggestions(
        batch.sourceText,
        batch.suggestions.map((s) => s.toDraft()).toList(growable: false),
        providerLabel: batch.providerLabel,
      );

  Future<List<ReviewActions>?> reviewedActions(String reviewId) async {
    final raw = await vault.repository.readLocalValue('agent.plan.$reviewId');
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map;
    if (data['version'] != 1) throw const FormatException('确认计划版本不支持');
    return [
      for (final action in data['actions'] as List)
        ReviewActions.fromJson(action as Map),
    ];
  }
}
