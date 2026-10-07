import '../ai/ai_provider_settings.dart';
import 'ai_provider.dart';

/// Device configuration and credentials. Implementations own secure storage;
/// neither application services nor presentation choose a storage plugin.
abstract interface class AiSettingsRepository {
  Future<AiProviderSettings> read();
  Future<List<AiProviderSettings>> readProfiles();
  Future<String?> readApiKey();
  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
  });
  Future<void> saveProfile({
    String? id,
    bool create = false,
    required String name,
    required String endpoint,
    required String model,
    required List<String> models,
    required AiProtocol protocol,
    required bool images,
    required bool files,
    bool audio = false,
    String? apiKey,
  });
  Future<void> saveProtocol(AiProtocol protocol);
  Future<void> saveCapabilities({
    required bool images,
    required bool files,
    bool audio = false,
  });
  Future<void> select(String id, String model);
  Future<void> remove(String id);
  Future<void> clear();
}
