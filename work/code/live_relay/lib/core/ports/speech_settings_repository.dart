import '../speech/remote_speech_settings.dart';

abstract interface class SpeechSettingsRepository {
  Future<RemoteSpeechSettings> read();
  Future<RemoteSpeechCredentials> readCredentials();
  Future<void> save({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  });
  Future<void> select(bool remote);
  Future<void> clear();
}
