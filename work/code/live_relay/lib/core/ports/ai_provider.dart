import 'dart:async';

import 'agent_command_provider.dart';
import '../ai/review_action_proposal.dart';

class AiCancellation {
  final _cancelled = Completer<void>();
  Future<void> get whenCancelled => _cancelled.future;
  bool get isCancelled => _cancelled.isCompleted;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }

  void check() {
    if (isCancelled) throw const FormatException('已取消本次 Agent 整理');
  }
}

enum AiProtocol { chatCompletions, responses }

class AiProviderRequest {
  const AiProviderRequest({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.redactedText,
    this.protocol = AiProtocol.chatCompletions,
    this.cancellation,
    this.commandSession,
    this.inputContent,
    this.reviewTargets = const [],
  });

  final List<Map<String, Object?>>? inputContent;
  final List<ReviewTarget> reviewTargets;
  final AiCancellation? cancellation;
  final AgentCommandSession? commandSession;
  final AiProtocol protocol;
  final Uri endpoint;
  final String apiKey;
  final String model;
  final String redactedText;
}

abstract interface class AiProvider {
  Future<String> organize(AiProviderRequest request);
}
