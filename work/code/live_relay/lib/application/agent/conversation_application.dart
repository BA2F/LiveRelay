import 'dart:typed_data';

import '../../core/ai/ai_privacy.dart';
import '../../core/ai/ai_provider_settings.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/review_action_proposal.dart';
import '../../core/ai/review_source.dart';
import '../../core/domain/entities.dart';
import '../../core/ports/ai_conversation_provider.dart';
import '../../core/ports/vault_lifecycle.dart';
import '../../core/ports/vault_repository.dart';
import '../vault_content_service.dart';
import '../vault_snapshot_query.dart';
import 'agent_review_service.dart';
import 'agent_service.dart';
import 'agent_settings_service.dart';

/// Conversation use cases are wired to application services and session ports,
/// never through a Flutter controller. Each new front end can use the same flow.
class ConversationApplication {
  const ConversationApplication({
    required this.vault,
    required this.settings,
    required this.agent,
    required this.review,
    required this.content,
    required this.snapshots,
  });
  final VaultLifecycle vault;
  final AgentSettingsService settings;
  final AgentService agent;
  final AgentReviewService review;
  final VaultContentService content;
  final VaultSnapshotQuery snapshots;
  bool get isUnlocked => vault.isUnlocked;
  AiProviderSettings get aiSettings => settings.settings;
  int get aiConfigurationGeneration => settings.generation;
  List<LifeCard> get cards => snapshots.current?.cards ?? const [];
  VaultRepository get _repository {
    if (!isUnlocked) throw StateError('请先解锁资料库');
    if (vault.isMaintaining) throw StateError('资料库维护正在进行');
    return vault.repository;
  }

  AiTokenizedPayload prepareConversationText(
    String text,
    List<SensitiveMark> marks,
  ) => agent.prepare(text, marks);
  Future<AiConversationResponse> converse(
    String text,
    List<Map<String, Object?>> history, {
    List<Map<String, Object?>>? inputContent,
    List<ReviewTarget> reviewTargets = const [],
  }) {
    if (vault.isMaintaining) throw const FormatException('请等待资料库维护完成');
    return agent.converse(
      text,
      history,
      inputContent: inputContent,
      reviewTargets: reviewTargets,
    );
  }

  void cancelAgentTask() => agent.cancel();
  Future<String?> readConversationState() async {
    final generation = vault.sessionGeneration;
    final value = await _repository.readChunkedLocalValue(
      'agent.conversation.v1',
    );
    _current(generation);
    return value;
  }

  Future<void> writeConversationState(String value) => vault.runMutation(
    () async {
      final generation = vault.sessionGeneration;
      await _repository.writeChunkedLocalValue('agent.conversation.v1', value);
      _current(generation);
    },
  );
  Future<Uint8List> readOriginal(String id) => content.readOriginal(id);
  Future<LifeCard> importOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) => vault
      .runMutation(() async {
        try {
          final generation = vault.sessionGeneration;
          _repository;
          final card = await content.importOriginal(
            bytes: bytes,
            originalName: originalName,
            mimeType: mimeType,
            mediaKind: mediaKind,
          );
          _current(generation);
          await snapshots.load();
          return card;
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      })
      .whenComplete(() => bytes.fillRange(0, bytes.length, 0));
  Future<List<CardSource>> cardSources(String id) =>
      _repository.cardSources(id);
  Future<void> acceptConversationCards(
    String reviewId,
    String sourceText,
    List<AiCardSuggestion> suggestions, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  }) => vault.runMutation(() async {
    final generation = vault.sessionGeneration;
    _repository;
    await review.accept(
      reviewId,
      sourceText,
      suggestions,
      providerLabel: providerLabel,
      originalIds: originalIds,
      reviewSource: reviewSource,
      actions: actions,
    );
    _current(generation);
    await snapshots.load();
  });
  Future<List<ReviewActions>?> reviewedActions(String id) {
    _repository;
    return review.reviewedActions(id);
  }

  void _current(int generation) {
    if (!isUnlocked || generation != vault.sessionGeneration) {
      throw StateError('资料库已关闭或重开');
    }
  }
}
