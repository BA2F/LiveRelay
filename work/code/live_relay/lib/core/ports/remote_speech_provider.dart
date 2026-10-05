import 'dart:typed_data';

import 'ai_provider.dart';

enum RemoteSpeechProtocol { openAiMultipart }

class RemoteSpeechRequest {
  const RemoteSpeechRequest({
    required this.endpoint,
    required this.apiKey,
    required this.model,
    required this.wav,
    required this.cancellation,
  });
  final Uri endpoint;
  final String apiKey, model;
  final Uint8List wav;
  final AiCancellation cancellation;
}

abstract interface class RemoteSpeechProvider {
  Future<String> transcribe(RemoteSpeechRequest request);
}
