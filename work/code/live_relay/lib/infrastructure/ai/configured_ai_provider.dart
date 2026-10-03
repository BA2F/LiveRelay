import '../../core/ports/ai_provider.dart';
import 'openai_compatible_provider.dart';
import 'responses_agent_provider.dart';

class ConfiguredAiProvider implements AiProvider {
  ConfiguredAiProvider({AiProvider? chat, AiProvider? responses})
    : _chat = chat ?? OpenAiCompatibleProvider(),
      _responses = responses ?? ResponsesAgentProvider();
  final AiProvider _chat;
  final AiProvider _responses;
  @override
  Future<String> organize(AiProviderRequest request) =>
      (request.protocol == AiProtocol.responses ? _responses : _chat).organize(
        request,
      );
}
