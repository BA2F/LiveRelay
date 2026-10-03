import '../../core/ports/ai_provider.dart';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AiProviderSettings {
  const AiProviderSettings({
    required this.endpoint,
    required this.model,
    required this.hasApiKey,
    this.protocol = AiProtocol.chatCompletions,
  });

  final AiProtocol protocol;
  final String endpoint;
  final String model;
  final bool hasApiKey;

  bool get isConfigured =>
      endpoint.trim().isNotEmpty && model.trim().isNotEmpty && hasApiKey;
}

class AiProviderSettingsStore {
  AiProviderSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'liverelay_ai_provider_v1',
            ),
          );

  static const _endpointKey = 'endpoint';
  static const _modelKey = 'model';
  static const _apiKey = 'api-key';
  static const _protocolKey = 'protocol';

  final FlutterSecureStorage _storage;

  Future<AiProviderSettings> read() async {
    final values = await _storage.readAll();
    return AiProviderSettings(
      protocol: values[_protocolKey] == 'responses'
          ? AiProtocol.responses
          : AiProtocol.chatCompletions,
      endpoint: values[_endpointKey] ?? '',
      model: values[_modelKey] ?? '',
      hasApiKey: (values[_apiKey] ?? '').isNotEmpty,
    );
  }

  Future<String?> readApiKey() => _storage.read(key: _apiKey);

  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    final parsed = Uri.tryParse(endpoint.trim());
    if (parsed == null || parsed.scheme != 'https' || parsed.host.isEmpty) {
      throw const FormatException('Endpoint 必须是 HTTPS 地址');
    }
    if (model.trim().isEmpty) throw const FormatException('请填写模型名称');
    await _storage.write(key: _endpointKey, value: parsed.toString());
    await _storage.write(key: _modelKey, value: model.trim());
    if (apiKey != null && apiKey.trim().isNotEmpty) {
      await _storage.write(key: _apiKey, value: apiKey.trim());
    }
  }

  Future<void> saveProtocol(AiProtocol protocol) =>
      _storage.write(key: _protocolKey, value: protocol.name);

  Future<void> clear() => _storage.deleteAll();
}
