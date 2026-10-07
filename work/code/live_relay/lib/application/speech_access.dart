import 'package:flutter/foundation.dart';

import '../infrastructure/speech/remote_speech_settings_store.dart';

/// Model controls and public status only; contains no credential access.
abstract interface class SpeechAccess implements Listenable {
  bool get usingRemote;
  bool get ready;
  bool get supported;
  bool get installed;
  bool get busy;
  int get received;
  int? get total;
  String? get error;
  RemoteSpeechSettings get remoteSettings;
  Future<void> chooseRemote(bool remote);
  Future<void> download();
  Future<void> install(String path);
  Future<void> remove();
  Future<void> cancel();
  void cancelTranscription();
}
