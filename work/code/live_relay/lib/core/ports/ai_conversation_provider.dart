import 'ai_provider.dart';

class AiConversationResponse {
  const AiConversationResponse({required this.content, required this.output});
  final String content;
  final List<Map<String, Object?>> output;
}

abstract interface class AiConversationProvider {
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  );
}
