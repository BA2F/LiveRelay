import '../../core/ports/ai_provider.dart';
import '../../core/ports/ai_conversation_provider.dart';
import 'http_conversation_provider.dart';
import 'openai_compatible_provider.dart';
import 'responses_agent_provider.dart';

class ConfiguredAiProvider implements AiProvider, AiConversationProvider {
  ConfiguredAiProvider({AiProvider? chat, AiProvider? responses})
    : _chat = chat ?? OpenAiCompatibleProvider(),
      _responses = responses ?? ResponsesAgentProvider();
  final AiConversationProvider _conversation = HttpConversationProvider();
  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) => _conversation.converse(request, history);
  final AiProvider _chat;
  final AiProvider _responses;
  @override
  Future<String> organize(AiProviderRequest request) =>
      (request.protocol == AiProtocol.responses ? _responses : _chat).organize(
        request,
      );
}
