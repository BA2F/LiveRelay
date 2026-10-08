import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/speech/speech_runtime.dart';
import '../contracts/speech_access.dart';
import '../../core/speech/remote_speech_settings.dart';

/// Adapts pure application state to Flutter's Listenable contract.
class SpeechService extends ChangeNotifier implements SpeechAccess {
  SpeechService(this.runtime) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final SpeechRuntime runtime;
  late final StreamSubscription<SpeechStatus> _subscription;
  @override
  RemoteSpeechSettings get remoteSettings => runtime.remoteSettings;
  int get configurationGeneration => runtime.configurationGeneration;
  @override
  bool get usingRemote => runtime.usingRemote;
  @override
  bool get ready => runtime.ready;
  @override
  bool get supported => runtime.supported;
  @override
  bool get installed => runtime.installed;
  @override
  bool get busy => runtime.busy;
  @override
  int get received => runtime.received;
  @override
  int? get total => runtime.total;
  @override
  String? get error => runtime.error;
  Future<void> refresh() => runtime.refresh();
  Future<void> configureRemote({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  }) => runtime.configureRemote(
    name: name,
    endpoint: endpoint,
    model: model,
    apiKey: apiKey,
  );
  @override
  Future<void> chooseRemote(bool remote) => runtime.chooseRemote(remote);
  Future<void> clearRemote() => runtime.clearRemote();
  @override
  Future<void> download() => runtime.download();
  @override
  Future<void> install(String path) => runtime.install(path);
  @override
  Future<void> remove() => runtime.remove();
  @override
  Future<void> cancel() => runtime.cancel();
  @override
  void cancelTranscription() => runtime.cancelTranscription();
  Future<String> transcribe(Uint8List wav, {int? authorizedRemoteGeneration}) =>
      runtime.transcribe(
        wav,
        authorizedRemoteGeneration: authorizedRemoteGeneration,
      );
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
