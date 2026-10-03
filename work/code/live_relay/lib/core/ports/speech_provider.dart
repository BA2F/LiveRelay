import 'dart:typed_data';

typedef SpeechDownloadProgress = void Function(int received, int? total);

abstract interface class SpeechProvider {
  Future<bool> isModelInstalled();
  Future<void> downloadModel(SpeechDownloadProgress progress);
  Future<void> installArchive(String path);
  Future<void> removeModel();
  Future<void> cancelDownload();
  Future<String> transcribe(Uint8List wav);
}
