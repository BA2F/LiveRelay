import 'package:uuid/uuid.dart';

import 'conversation_attachment.dart';
import 'review_actions.dart';
import 'review_action_proposal.dart';
import 'ai_privacy.dart';

class PreparedConversationTurn {
  const PreparedConversationTurn(
    this.text,
    this.payload,
    this.generation,
    this.turn,
    this.provider,
    this.attachments,
    this.configurationGeneration,
    this.reviewTargets,
  );
  final List<ConversationAttachment> attachments;
  final List<ReviewTarget> reviewTargets;
  final int generation, turn;
  final int configurationGeneration;
  final String provider;
  final String text;
  final AiTokenizedPayload payload;
}

class ConversationMessage {
  ConversationMessage(
    this.role,
    this.text, {
    List<AiCardSuggestion> suggestions = const [],
    List<ReviewActions>? actions,
    List<ReviewActionProposal?>? proposals,
    String? reviewId,
    this.providerLabel = '',
    this.attachments = const [],
    this.accepted = false,
  }) : proposals = proposals == null
           ? List.filled(suggestions.length, null)
           : List.of(proposals),
       actions = actions == null
           ? List.generate(suggestions.length, (_) => const ReviewActions())
           : List.of(actions),
       suggestions = List.of(suggestions),
       reviewId = reviewId ?? const Uuid().v7() {
    if (this.actions.length != this.suggestions.length ||
        this.proposals.length != this.suggestions.length) {
      throw const FormatException('建议操作数量不匹配');
    }
    for (final proposal in this.proposals) {
      proposal?.validate();
    }
    for (final action in this.actions) {
      action.validate();
    }
  }
  final List<ConversationAttachment> attachments;
  final String role, text, reviewId, providerLabel;
  final List<AiCardSuggestion> suggestions;
  final List<ReviewActions> actions;
  final List<ReviewActionProposal?> proposals;
  bool accepted;
}
