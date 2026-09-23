class AiProviderRequest {
  const AiProviderRequest({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.redactedText,
  });

  final Uri endpoint;
  final String apiKey;
  final String model;
  final String redactedText;
}

abstract interface class AiProvider {
  Future<String> organize(AiProviderRequest request);
}
