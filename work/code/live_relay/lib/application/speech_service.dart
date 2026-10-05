import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ports/speech_provider.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/remote_speech_provider.dart';
import '../infrastructure/speech/http_remote_speech_provider.dart';
import '../infrastructure/speech/remote_speech_settings_store.dart';

class SpeechService extends ChangeNotifier {
  SpeechService(
    this.provider, {
    bool? supported,
    RemoteSpeechProvider? remoteProvider,
    RemoteSpeechSettingsStore? settingsStore,
  }) : supported =
           supported ??
           (Platform.isAndroid || Platform.isLinux || Platform.isWindows),
       remoteProvider = remoteProvider ?? HttpRemoteSpeechProvider(),
       settingsStore = settingsStore ?? RemoteSpeechSettingsStore(),
       _ownsRemote = remoteProvider == null;
  final SpeechProvider provider;
  final RemoteSpeechProvider remoteProvider;
  final RemoteSpeechSettingsStore settingsStore;
  final bool _ownsRemote;
  RemoteSpeechSettings remoteSettings = const RemoteSpeechSettings();
  bool get usingRemote => remoteSettings.selected;
  bool get ready =>
      usingRemote ? remoteSettings.configured : supported && installed;
  int configurationGeneration = 0;
  AiCancellation? _transcription;
  void cancelTranscription() => _transcription?.cancel();
  Future<void> configureRemote({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  }) => _run(() async {
    configurationGeneration++;
    await settingsStore.save(
      name: name,
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
    );
  }, requiresLocal: false);
  Future<void> chooseRemote(bool remote) => _run(() async {
    configurationGeneration++;
    await settingsStore.select(remote);
  }, requiresLocal: false);
  Future<void> clearRemote() => _run(() async {
    configurationGeneration++;
    await settingsStore.clear();
  }, requiresLocal: false);
  final bool supported;
  bool installed = false;
  bool busy = false;
  int received = 0;
  int? total;
  String? error;
  bool _disposed = false;
  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> refresh() async {
    try {
      remoteSettings = await settingsStore.read();
    } on Object {
      remoteSettings = const RemoteSpeechSettings();
      error ??= '无法读取远程语音配置，原配置已保留';
    }
    try {
      installed = supported && await provider.isModelInstalled();
    } on Object {
      installed = false;
      error ??= '无法检查语音模型，请检查存储空间';
    }
    _changed();
  }

  Future<void> _run(
    Future<void> Function() operation, {
    bool requiresLocal = true,
  }) async {
    if (requiresLocal && !supported) throw UnsupportedError('当前平台尚未支持本地语音识别');
    if (busy) throw StateError('请等待当前语音操作完成');
    busy = true;
    error = null;
    _changed();
    try {
      await operation();
    } on Object catch (e) {
      error = e is FormatException ? e.message : '语音操作失败，请检查配置或稍后重试';
      rethrow;
    } finally {
      busy = false;
      await refresh();
    }
  }

  Future<void> download() => _run(
    () => provider.downloadModel((r, t) {
      received = r;
      total = t;
      _changed();
    }),
  );
  Future<void> install(String path) =>
      _run(() => provider.installArchive(path));
  Future<void> remove() => _run(provider.removeModel);
  Future<void> cancel() => provider.cancelDownload();
  Future<String> transcribe(
    Uint8List wav, {
    int? authorizedRemoteGeneration,
  }) async {
    late String result;
    try {
      final remote = usingRemote;
      final generation = configurationGeneration;
      final settings = remoteSettings;
      await _run(() async {
        if (!remote) {
          result = await provider.transcribe(wav);
          return;
        }
        if (authorizedRemoteGeneration != generation || !settings.configured) {
          throw const FormatException('请重新核对并允许本次音频上传');
        }
        final cancellation = AiCancellation();
        _transcription = cancellation;
        try {
          final key = await settingsStore.readApiKey();
          cancellation.check();
          if (key == null ||
              key.isEmpty ||
              generation != configurationGeneration) {
            throw const FormatException('语音服务配置已变化，请重新确认');
          }
          result = await remoteProvider.transcribe(
            RemoteSpeechRequest(
              endpoint: Uri.parse(settings.endpoint),
              apiKey: key,
              model: settings.model,
              wav: wav,
              cancellation: cancellation,
            ),
          );
          cancellation.check();
        } finally {
          if (identical(_transcription, cancellation)) _transcription = null;
        }
      }, requiresLocal: !remote);
      return result;
    } finally {
      wav.fillRange(0, wav.length, 0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    cancelTranscription();
    provider.cancelDownload();
    if (_ownsRemote && remoteProvider is HttpRemoteSpeechProvider) {
      (remoteProvider as HttpRemoteSpeechProvider).close();
    }
    super.dispose();
  }
}
