import 'dart:async';

import '../../core/ai/ai_provider_settings.dart';
import '../../core/ports/ai_provider.dart';
import '../../core/ports/ai_settings_repository.dart';

/// Frontend-independent configuration use cases. A generation changes before
/// any credential write, including a failed write, invalidating reviewed scope.
class AgentSettingsService {
  AgentSettingsService(this._repository);
  final AiSettingsRepository _repository;
  final _changes = StreamController<int>.broadcast(sync: true);
  static const empty = AiProviderSettings(
    endpoint: '',
    model: '',
    hasApiKey: false,
  );
  AiProviderSettings _settings = empty;
  List<AiProviderSettings> _profiles = const [];
  int _generation = 0;
  bool _changing = false;
  bool _disposed = false;
  AiProviderSettings get settings => _settings;
  List<AiProviderSettings> get profiles => _profiles;
  int get generation => _generation;
  Stream<int> get changes => _changes.stream;

  Future<void> initialize() async {
    try {
      await _reload();
    } on Object {
      _settings = empty;
      _profiles = const [];
    }
  }

  Future<void> _reload() async {
    final settings = await _repository.read();
    final profiles = await _repository.readProfiles();
    _settings = settings;
    _profiles = List.unmodifiable(profiles);
  }

  Future<void> _change(Future<void> Function() action) async {
    if (_disposed) throw const FormatException('服务配置已关闭');
    if (_changing) throw const FormatException('请等待当前服务配置保存完成');
    _changing = true;
    _generation++;
    _changes.add(_generation);
    try {
      await action();
      if (!_disposed) _changes.add(_generation);
    } finally {
      _changing = false;
    }
  }

  Future<String?> readApiKey() => _repository.readApiKey();

  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
    AiProtocol? protocol,
    bool? supportsImages,
    bool? supportsFiles,
    bool? supportsAudio,
    String? profileId,
    String? name,
    List<String>? models,
    bool create = false,
  }) => _change(() async {
    if (name != null) {
      await _repository.saveProfile(
        id: profileId,
        create: create,
        name: name,
        endpoint: endpoint,
        model: model,
        models: models ?? [model],
        protocol: protocol ?? settings.protocol,
        images: supportsImages ?? false,
        files: supportsFiles ?? false,
        audio: supportsAudio ?? false,
        apiKey: apiKey,
      );
    } else {
      await _repository.save(endpoint: endpoint, model: model, apiKey: apiKey);
      if (protocol != null) await _repository.saveProtocol(protocol);
      if (supportsImages != null ||
          supportsFiles != null ||
          supportsAudio != null) {
        await _repository.saveCapabilities(
          images: supportsImages ?? settings.supportsImages,
          files: supportsFiles ?? settings.supportsFiles,
          audio: supportsAudio ?? settings.supportsAudio,
        );
      }
    }
    await _reload();
  });

  Future<void> select(String id, String model) => _change(() async {
    await _repository.select(id, model);
    await _reload();
  });

  Future<void> remove(String id) => _change(() async {
    await _repository.remove(id);
    await _reload();
  });

  Future<void> clear() => _change(() async {
    await _repository.clear();
    _settings = empty;
    _profiles = const [];
  });

  void dispose() {
    _disposed = true;
    unawaited(_changes.close());
  }
}
