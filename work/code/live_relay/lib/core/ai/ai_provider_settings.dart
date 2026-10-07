import '../ports/ai_provider.dart';

class AiProviderSettings {
  const AiProviderSettings({
    required this.endpoint,
    required this.model,
    required this.hasApiKey,
    this.id = 'legacy',
    this.name = 'AI 服务',
    this.models = const [],
    this.protocol = AiProtocol.chatCompletions,
    this.supportsImages = false,
    this.supportsFiles = false,
    this.supportsAudio = false,
  });
  final String id, name;
  final List<String> models;
  final bool supportsImages, supportsFiles, supportsAudio;
  final AiProtocol protocol;
  final String endpoint, model;
  final bool hasApiKey;
  bool get isConfigured =>
      endpoint.trim().isNotEmpty && model.trim().isNotEmpty && hasApiKey;
}
