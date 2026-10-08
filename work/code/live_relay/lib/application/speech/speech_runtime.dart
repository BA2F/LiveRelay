import 'dart:async';
import 'dart:typed_data';

import '../../core/ports/ai_provider.dart';
import '../../core/ports/speech_provider.dart';
import '../../core/ports/remote_speech_provider.dart';
import '../../core/ports/speech_settings_repository.dart';
import '../../core/speech/remote_speech_settings.dart';

/// A notification contains public status only, never a key or audio buffer.
class SpeechStatus {
  const SpeechStatus({
    required this.busy,
    required this.installed,
    required this.received,
    this.total,
    this.error,
  });
  final bool busy, installed;
  final int received;
  final int? total;
  final String? error;
}

/// Pure application flow. Platform capability, storage, providers and resource
/// ownership are injected by composition; UI subscribes through an adapter.
class SpeechRuntime {
  SpeechRuntime({
    required this.provider,
    required this.remoteProvider,
    required this.settingsRepository,
    required this.supported,
    this.disposeRemote,
  });
  final SpeechProvider provider;
  final RemoteSpeechProvider remoteProvider;
  final SpeechSettingsRepository settingsRepository;
  final bool supported;
  final void Function()? disposeRemote;
  final _changes = StreamController<SpeechStatus>.broadcast();
  Stream<SpeechStatus> get changes => _changes.stream;
  RemoteSpeechSettings _settings = const RemoteSpeechSettings();
  RemoteSpeechSettings get remoteSettings => _settings;
  bool get usingRemote => _settings.selected;
  bool get ready => usingRemote
      ? _settingsReadable && _settings.configured
      : supported && installed;
  int _configurationGeneration = 0;
  int get configurationGeneration => _configurationGeneration;
  bool _settingsReadable = false;
  AiCancellation? _transcription;
  bool _installed = false, _busy = false, _disposed = false;
  int _received = 0;
  int? _total;
  String? _error;
  bool get installed => _installed;
  bool get busy => _busy;
  int get received => _received;
  int? get total => _total;
  String? get error => _error;

  void _changed() {
    if (!_disposed) {
      _changes.add(
        SpeechStatus(
          busy: busy,
          installed: installed,
          received: received,
          total: total,
          error: error,
        ),
      );
    }
  }

  void _active() {
    if (_disposed) throw StateError('语音服务已销毁');
  }

  void cancelTranscription() => _transcription?.cancel();
  Future<void> configureRemote({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  }) => _run(() async {
    _configurationGeneration++;
    _settingsReadable = false;
    await settingsRepository.save(
      name: name,
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
    );
  }, requiresLocal: false);
  Future<void> chooseRemote(bool remote) => _run(() async {
    _configurationGeneration++;
    _settingsReadable = false;
    await settingsRepository.select(remote);
  }, requiresLocal: false);
  Future<void> clearRemote() => _run(() async {
    _configurationGeneration++;
    _settingsReadable = false;
    await settingsRepository.clear();
  }, requiresLocal: false);

  (String, String, String, RemoteSpeechProtocol, bool, bool) _fingerprint(
    RemoteSpeechSettings s,
  ) => (s.name, s.endpoint, s.model, s.protocol, s.hasApiKey, s.selected);

  Future<void> refresh() async {
    _active();
    if (busy) return;
    _busy = true;
    try {
      await _refresh();
    } finally {
      _busy = false;
      _changed();
    }
  }

  Future<void> _refresh() async {
    if (_disposed) return;
    try {
      final next = await settingsRepository.read();
      if (_disposed) return;
      if (_fingerprint(next) != _fingerprint(_settings)) {
        _configurationGeneration++;
      }
      _settings = next;
      _settingsReadable = true;
    } on Object {
      // Keep the last selected mode, while disabling remote eligibility. A
      // failed read must not silently route a remote request to the local path.
      _settingsReadable = false;
      _configurationGeneration++;
      _error ??= '无法读取远程语音配置，原配置已保留';
    }
    try {
      final next = supported && await provider.isModelInstalled();
      if (!_disposed) _installed = next;
    } on Object {
      _installed = false;
      _error ??= '无法检查语音模型，请检查存储空间';
    }
  }

  Future<void> _run(
    Future<void> Function() operation, {
    bool requiresLocal = true,
  }) async {
    _active();
    if (requiresLocal && !supported) throw UnsupportedError('当前平台尚未支持本地语音识别');
    if (busy) throw StateError('请等待当前语音操作完成');
    _busy = true;
    _error = null;
    _changed();
    try {
      await operation();
      _active();
    } on Object catch (e) {
      if (!_disposed) {
        _error = e is FormatException ? e.message : '语音操作失败，请检查配置或稍后重试';
      }
      rethrow;
    } finally {
      try {
        await _refresh();
      } finally {
        _busy = false;
        _changed();
      }
    }
  }

  Future<void> download() => _run(
    () => provider.downloadModel((r, t) {
      if (_disposed) return;
      _received = r;
      _total = t;
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
    AiCancellation? cancellation;
    late String result;
    try {
      final remote = usingRemote;
      final generation = configurationGeneration;
      final settings = remoteSettings;
      await _run(() async {
        final token = cancellation = AiCancellation();
        _transcription = token;
        if (!remote) {
          result = await provider.transcribe(wav);
        } else {
          if (!_settingsReadable ||
              authorizedRemoteGeneration != generation ||
              !settings.configured) {
            throw const FormatException('请重新核对并允许本次音频上传');
          }
          final credentials = await settingsRepository.readCredentials();
          token.check();
          _active();
          final key = credentials.apiKey;
          if (key == null ||
              key.isEmpty ||
              generation != configurationGeneration ||
              _fingerprint(credentials.settings) != _fingerprint(settings)) {
            throw const FormatException('语音服务配置已变化，请重新确认');
          }
          result = await remoteProvider.transcribe(
            RemoteSpeechRequest(
              endpoint: Uri.parse(settings.endpoint),
              apiKey: key,
              model: settings.model,
              wav: wav,
              cancellation: token,
            ),
          );
        }
        token.check();
        _active();
      }, requiresLocal: !remote);
      _active();
      cancellation?.check();
      return result;
    } finally {
      if (cancellation != null && identical(_transcription, cancellation)) {
        _transcription = null;
      }
      wav.fillRange(0, wav.length, 0);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelTranscription();
    unawaited(provider.cancelDownload().catchError((Object _) {}));
    try {
      disposeRemote?.call();
    } finally {
      unawaited(_changes.close());
    }
  }
}
