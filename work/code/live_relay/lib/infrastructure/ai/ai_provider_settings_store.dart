import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

import '../../core/ports/ai_provider.dart';
import '../../core/ai/ai_service_endpoint.dart';

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

/// Device credentials remain in secure storage, independently of vault content.
/// One versioned write changes profile settings and key together.
class AiProviderSettingsStore {
  AiProviderSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'liverelay_ai_provider_v1',
            ),
          );
  final FlutterSecureStorage _storage;
  static const _catalogKey = 'liverelay.ai.profiles.v2';
  static const _legacyKeys = [
    'endpoint',
    'model',
    'api-key',
    'protocol',
    'supports-images',
    'supports-files',
  ];

  Future<Map<String, dynamic>> _load() async {
    final raw = await _storage.read(key: _catalogKey);
    if (raw != null) {
      if (raw.length > 256 * 1024) throw const FormatException('AI 服务配置过大');
      final data = jsonDecode(raw);
      if (data is! Map ||
          data['version'] != 2 ||
          data['profiles'] is! List ||
          (data['profiles'] as List).length > 24) {
        throw const FormatException('AI 服务配置无法读取，原配置已保留');
      }
      final result = Map<String, dynamic>.from(data);
      final ids = <String>{};
      for (final entry in result['profiles'] as List) {
        final item = Map<String, dynamic>.from(entry as Map);
        final settings = _settings(item);
        if (!ids.add(settings.id)) throw const FormatException('AI 服务配置重复');
      }
      return result;
    }
    final values = await _storage.readAll();
    final legacy = <String, dynamic>{
      'id': 'legacy',
      'name': 'AI 服务',
      'endpoint': values['endpoint'] ?? '',
      'model': values['model'] ?? '',
      'key': values['api-key'] ?? '',
      'protocol': values['protocol'] ?? 'chatCompletions',
      'models': [if ((values['model'] ?? '').isNotEmpty) values['model']],
      'images': values['supports-images'] == 'true',
      'files': values['supports-files'] == 'true',
    };
    return {
      'version': 2,
      'active': 'legacy',
      'profiles': [if ((legacy['endpoint'] as String).isNotEmpty) legacy],
    };
  }

  AiProviderSettings _settings(Map item) => AiProviderSettings(
    id: item['id'] as String,
    name: item['name'] as String,
    endpoint: resolveAiEndpoint(
      Uri.parse(item['endpoint'] as String),
      AiProtocol.values.byName(item['protocol'] as String),
    ).toString(),
    model: item['model'] as String,
    models: List<String>.unmodifiable((item['models'] as List).cast<String>()),
    hasApiKey: (item['key'] as String).isNotEmpty,
    protocol: AiProtocol.values.byName(item['protocol'] as String),
    supportsImages: item['images'] == true,
    supportsFiles: item['files'] == true,
    supportsAudio: item['audio'] == true,
  );
  static const empty = AiProviderSettings(
    endpoint: '',
    model: '',
    hasApiKey: false,
  );
  Map<String, dynamic>? _active(Map<String, dynamic> data) {
    for (final p in data['profiles'] as List) {
      if (p['id'] == data['active']) return Map<String, dynamic>.from(p as Map);
    }
    return null;
  }

  Future<AiProviderSettings> read() async {
    final item = _active(await _load());
    return item == null ? empty : _settings(item);
  }

  Future<List<AiProviderSettings>> readProfiles() async => [
    for (final p in (await _load())['profiles'] as List) _settings(p as Map),
  ];
  Future<String?> readApiKey() async =>
      _active(await _load())?['key'] as String?;
  Future<void> _write(Map<String, dynamic> data) async {
    await _storage.write(key: _catalogKey, value: jsonEncode(data));
    for (final key in _legacyKeys) {
      await _storage.delete(key: key);
    }
  }

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
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('服务地址必须是无内嵌凭据的 HTTPS 地址');
    }
    if (name.trim().isEmpty ||
        name.length > 80 ||
        model.trim().isEmpty ||
        model.length > 200) {
      throw const FormatException('请填写服务名称和模型名称');
    }
    final choices = {
      model.trim(),
      ...models.map((v) => v.trim()).where((v) => v.isNotEmpty),
    }.toList();
    if (choices.length > 24 || choices.any((v) => v.length > 200)) {
      throw const FormatException('每个服务最多 24 个模型');
    }
    final data = await _load();
    final selectedId = create
        ? const Uuid().v7()
        : id ?? data['active'] as String;
    final profiles = List<Map<String, dynamic>>.from(
      (data['profiles'] as List).map(
        (p) => Map<String, dynamic>.from(p as Map),
      ),
    );
    final index = profiles.indexWhere((p) => p['id'] == selectedId);
    if (index < 0 && profiles.length >= 24) {
      throw const FormatException('最多 24 个 AI 服务');
    }
    final previous = index < 0 ? null : profiles[index];
    final item = <String, dynamic>{
      'id': selectedId,
      'name': name.trim(),
      'endpoint': resolveAiEndpoint(uri, protocol).toString(),
      'model': model.trim(),
      'models': choices,
      'protocol': protocol.name,
      'images': images,
      'files': files,
      'audio': audio,
      'key': apiKey?.trim().isNotEmpty == true
          ? apiKey!.trim()
          : previous?['key'] ?? '',
    };
    if (index < 0) {
      profiles.add(item);
    } else {
      profiles[index] = item;
    }
    await _write({'version': 2, 'active': selectedId, 'profiles': profiles});
  }

  Future<void> select(String id, String model) async {
    final data = await _load();
    final profiles = data['profiles'] as List;
    final item = profiles.cast<Map>().firstWhere(
      (p) => p['id'] == id,
      orElse: () => throw const FormatException('AI 服务不存在'),
    );
    if (!(item['models'] as List).contains(model)) {
      throw const FormatException('模型不在此服务的配置中');
    }
    item['model'] = model;
    data['active'] = id;
    await _write(data);
  }

  Future<void> remove(String id) async {
    final data = await _load();
    final profiles = data['profiles'] as List;
    profiles.removeWhere((p) => p['id'] == id);
    if (data['active'] == id) {
      data['active'] = profiles.isEmpty ? '' : profiles.first['id'];
    }
    await _write(data);
  }

  // Keep the existing mobile callers on the selected device profile.
  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    final previous = await read();
    await saveProfile(
      name: previous.name,
      endpoint: endpoint,
      model: model,
      models: previous.models,
      protocol: previous.protocol,
      images: previous.supportsImages,
      files: previous.supportsFiles,
      audio: previous.supportsAudio,
      apiKey: apiKey,
    );
  }

  Future<void> saveProtocol(AiProtocol protocol) async {
    final data = await _load();
    final item = _active(data);
    if (item == null) throw const FormatException('请先配置 AI 服务');
    for (final p in data['profiles'] as List) {
      if (p['id'] == item['id']) p['protocol'] = protocol.name;
    }
    await _write(data);
  }

  Future<void> saveCapabilities({
    required bool images,
    required bool files,
    bool audio = false,
  }) async {
    final data = await _load();
    for (final p in data['profiles'] as List) {
      if (p['id'] == data['active']) {
        p['images'] = images;
        p['files'] = files;
        p['audio'] = audio;
      }
    }
    await _write(data);
  }

  Future<void> clear() async {
    await _storage.delete(key: _catalogKey);
    for (final key in _legacyKeys) {
      await _storage.delete(key: key);
    }
  }
}
