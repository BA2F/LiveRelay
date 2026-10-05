import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/ports/remote_speech_provider.dart';

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

class RemoteSpeechSettingsStore {
  RemoteSpeechSettingsStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'liverelay_speech_provider_v1',
            ),
          );
  final FlutterSecureStorage _storage;
  // Unique key also isolates Linux/macOS/Windows storage from AI profiles.
  static const _key = 'liverelay.remote-speech.v1';
  Future<Map<String, dynamic>> _load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    if (raw.length > 32000) throw const FormatException('语音服务配置过大');
    final data = jsonDecode(raw);
    if (data is! Map || data['version'] != 1) {
      throw const FormatException('语音服务配置无法读取，原配置已保留');
    }
    return Map<String, dynamic>.from(data);
  }

  Future<RemoteSpeechSettings> read() async {
    final d = await _load();
    return RemoteSpeechSettings(
      name: d['name'] as String? ?? '远程语音服务',
      endpoint: d['endpoint'] as String? ?? '',
      model: d['model'] as String? ?? '',
      selected: d['selected'] == true,
      hasApiKey: (d['key'] as String? ?? '').isNotEmpty,
      protocol: RemoteSpeechProtocol.values.byName(
        d['protocol'] as String? ?? 'openAiMultipart',
      ),
    );
  }

  Future<String?> readApiKey() async => (await _load())['key'] as String?;
  Future<void> save({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    final uri = Uri.tryParse(endpoint.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      throw const FormatException('语音服务地址必须是无内嵌凭据的 HTTPS 地址');
    }
    if (name.trim().isEmpty ||
        name.length > 80 ||
        model.trim().isEmpty ||
        model.length > 200) {
      throw const FormatException('请填写语音服务和模型名称');
    }
    final old = await _load();
    await _storage.write(
      key: _key,
      value: jsonEncode({
        'version': 1,
        'name': name.trim(),
        'endpoint': uri.toString(),
        'model': model.trim(),
        'protocol': RemoteSpeechProtocol.openAiMultipart.name,
        'selected': old['selected'] == true,
        'key': apiKey?.trim().isNotEmpty == true
            ? apiKey!.trim()
            : old['key'] ?? '',
      }),
    );
  }

  Future<void> select(bool remote) async {
    if (remote && !(await read()).configured) {
      throw const FormatException('请先配置远程语音服务');
    }
    final d = await _load();
    d['version'] = 1;
    d['selected'] = remote;
    await _storage.write(key: _key, value: jsonEncode(d));
  }

  Future<void> clear() => _storage.delete(key: _key);
}
