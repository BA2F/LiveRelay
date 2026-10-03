import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/ports/speech_provider.dart';

class SpeechService extends ChangeNotifier {
  SpeechService(this.provider, {bool? supported})
    : supported =
          supported ??
          (Platform.isAndroid || Platform.isLinux || Platform.isWindows);
  final SpeechProvider provider;
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
      installed = supported && await provider.isModelInstalled();
    } on Object {
      installed = false;
      error ??= '无法检查语音模型，请检查存储空间';
    }
    _changed();
  }

  Future<void> _run(Future<void> Function() operation) async {
    if (!supported) throw UnsupportedError('当前平台尚未支持本地语音识别');
    if (busy) throw StateError('请等待当前语音操作完成');
    busy = true;
    error = null;
    _changed();
    try {
      await operation();
    } on Object catch (e) {
      error = e is FormatException ? e.message : '本地语音操作失败，请检查模型或稍后重试';
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
  Future<String> transcribe(Uint8List wav) async {
    late String result;
    try {
      await _run(() async {
        result = await provider.transcribe(wav);
      });
      return result;
    } finally {
      wav.fillRange(0, wav.length, 0);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    provider.cancelDownload();
    super.dispose();
  }
}
