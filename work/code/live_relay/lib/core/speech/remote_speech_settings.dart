import '../ports/remote_speech_provider.dart';

class RemoteSpeechSettings {
  const RemoteSpeechSettings({
    this.name = '远程语音服务',
    this.endpoint = '',
    this.model = '',
    this.hasApiKey = false,
    this.selected = false,
    this.protocol = RemoteSpeechProtocol.openAiMultipart,
  });
  final String name, endpoint, model;
  final bool hasApiKey, selected;
  final RemoteSpeechProtocol protocol;
  bool get configured => endpoint.isNotEmpty && model.isNotEmpty && hasApiKey;
}

/// One atomic settings/credential read; never included in presentation state.
class RemoteSpeechCredentials {
  const RemoteSpeechCredentials(this.settings, this.apiKey);
  final RemoteSpeechSettings settings;
  final String? apiKey;
}
