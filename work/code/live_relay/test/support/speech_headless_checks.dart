// Run with ordinary Dart. Providers/configuration are explicit in-memory ports.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_relay/application/speech/speech_runtime.dart';
import 'package:live_relay/core/ports/speech_provider.dart';
import 'package:live_relay/core/ports/remote_speech_provider.dart';
import 'package:live_relay/core/ports/speech_settings_repository.dart';
import 'package:live_relay/core/speech/remote_speech_settings.dart';

void check(bool v, String message) {
  if (!v) throw StateError(message);
}

Future<void> reject(Future<Object?> f, String message) async {
  Object? error;
  try {
    await f;
  } on Object catch (e) {
    error = e;
  }
  check(
    error != null && '$error'.contains(message),
    'Expected $message; got $error',
  );
}

Uint8List audio() => Uint8List.fromList([1, 2, 3]);
bool wiped(Uint8List bytes) => bytes.every((v) => v == 0);
Map<String, Future<void> Function()> speechChecks() => {
  'headless local default never reads remote credentials and wipes audio':
      () async {
        final f = Fixture();
        try {
          await f.runtime.refresh();
          final input = audio();
          check(
            await f.runtime.transcribe(input) == 'local fixture',
            'Local flow failed',
          );
          check(
            wiped(input) && f.remote.calls == 0 && f.store.credentialReads == 0,
            'Local leaked/uploaded audio',
          );
        } finally {
          f.runtime.dispose();
        }
      },
  'headless remote requires current consent and rejects an atomic mismatched endpoint/key pair':
      () async {
        final f = Fixture(remote: true);
        try {
          await f.runtime.refresh();
          final bytes = audio();
          await reject(f.runtime.transcribe(bytes), '核对');
          check(wiped(bytes) && f.remote.calls == 0, 'Unapproved upload');
          final consent = f.runtime.configurationGeneration;
          f.store.data = const RemoteSpeechSettings(
            endpoint: 'https://new.invalid/asr',
            model: 'new',
            hasApiKey: true,
            selected: true,
          );
          final mismatched = audio();
          await reject(
            f.runtime.transcribe(
              mismatched,
              authorizedRemoteGeneration: consent,
            ),
            '配置已变化',
          );
          check(
            wiped(mismatched) &&
                f.remote.calls == 0 &&
                f.store.credentialReads == 1,
            'Mismatched pair reached provider',
          );
        } finally {
          f.runtime.dispose();
        }
      },
  'headless speech partial settings write and unreadable cache block new uploads':
      () async {
        final f = Fixture(remote: true);
        try {
          await f.runtime.refresh();
          f.store.failAfterWrite = true;
          await reject(
            f.runtime.configureRemote(
              name: 'changed',
              endpoint: 'https://changed.invalid',
              model: 'changed',
              apiKey: 'changed-fixture-key',
            ),
            'fixture write failure',
          );
          check(
            !f.runtime.ready && !f.runtime.busy && f.runtime.usingRemote,
            'Failure eligibility leaked or changed route',
          );
          final bytes = audio();
          await reject(
            f.runtime.transcribe(
              bytes,
              authorizedRemoteGeneration: f.runtime.configurationGeneration,
            ),
            '核对',
          );
          check(
            wiped(bytes) &&
                f.remote.calls == 0 &&
                f.store.key == 'changed-fixture-key',
            'Stale endpoint used a new key or catalog deleted',
          );
        } finally {
          f.runtime.dispose();
        }
      },
  'headless disposal during local transcription discards late text and wipes input':
      () async {
        final f = Fixture();
        f.local.pending = Completer<String>();
        try {
          await f.runtime.refresh();
          final bytes = audio();
          final rejected = reject(f.runtime.transcribe(bytes), '取消');
          await f.local.started.future;
          f.runtime.dispose();
          f.local.pending!.complete('late local fixture');
          await rejected;
          check(
            wiped(bytes) && !f.runtime.busy && f.local.cancels == 1,
            'Dispose leaked local output/gate',
          );
        } finally {
          f.runtime.dispose();
        }
      },
  'headless transcription slot includes refresh, busy rejection wipes only its own audio, and cancellation covers readback':
      () async {
        final f = Fixture(remote: true);
        try {
          await f.runtime.refresh();
          f.store.pendingRead = Completer<RemoteSpeechSettings>();
          final firstAudio = audio();
          final rejected = reject(
            f.runtime.transcribe(
              firstAudio,
              authorizedRemoteGeneration: f.runtime.configurationGeneration,
            ),
            '取消',
          );
          await f.store.readbackEntered.future;
          final other = audio();
          await reject(
            f.runtime.transcribe(
              other,
              authorizedRemoteGeneration: f.runtime.configurationGeneration,
            ),
            '等待',
          );
          check(
            wiped(other) && !wiped(firstAudio) && f.runtime.busy,
            'Second operation altered running buffer/slot',
          );
          f.runtime.cancelTranscription();
          f.store.pendingRead!.complete(f.store.data);
          await rejected;
          check(
            wiped(firstAudio) && !f.runtime.busy && f.remote.calls == 1,
            'Readback cancellation lost',
          );
        } finally {
          f.runtime.dispose();
        }
      },
  'headless model progress emits public immutable status and owned remote disposal runs once':
      () async {
        var closes = 0;
        final f = Fixture(onDispose: () => closes++);
        final events = <SpeechStatus>[];
        final finished = Completer<void>();
        final subscription = f.runtime.changes.listen((event) {
          events.add(event);
          if (!event.busy && !finished.isCompleted) finished.complete();
        });
        try {
          await f.runtime.download();
          await finished.future;
          check(
            events.any((e) => e.received == 10 && e.total == 20) &&
                events.last.installed &&
                !events.last.busy,
            'Progress state lost',
          );
          f.runtime.dispose();
          f.runtime.dispose();
          check(closes == 1, 'Owned remote lifecycle repeated');
        } finally {
          await subscription.cancel();
          f.runtime.dispose();
        }
      },
};

class Fixture {
  Fixture({bool remote = false, void Function()? onDispose}) {
    if (remote) {
      store.data = const RemoteSpeechSettings(
        endpoint: 'https://fixture.invalid/asr',
        model: 'fixture',
        hasApiKey: true,
        selected: true,
      );
    }
    runtime = SpeechRuntime(
      provider: local,
      remoteProvider: this.remote,
      settingsRepository: store,
      supported: true,
      disposeRemote: onDispose,
    );
  }
  final Local local = Local();
  final Remote remote = Remote();
  final Store store = Store();
  late final SpeechRuntime runtime;
}

class Local implements SpeechProvider {
  int cancels = 0;
  Completer<String>? pending;
  final started = Completer<void>();
  @override
  Future<bool> isModelInstalled() async => true;
  @override
  Future<void> downloadModel(SpeechDownloadProgress progress) async {
    progress(10, 20);
  }

  @override
  Future<void> installArchive(String path) async {}
  @override
  Future<void> removeModel() async {}
  @override
  Future<void> cancelDownload() async {
    cancels++;
  }

  @override
  Future<String> transcribe(Uint8List wav) async {
    if (!started.isCompleted) started.complete();
    return pending == null ? 'local fixture' : await pending!.future;
  }
}

class Remote implements RemoteSpeechProvider {
  int calls = 0;
  @override
  Future<String> transcribe(RemoteSpeechRequest request) async {
    calls++;
    return 'remote fixture';
  }
}

class Store implements SpeechSettingsRepository {
  RemoteSpeechSettings data = const RemoteSpeechSettings();
  String key = 'fixture-key';
  bool failAfterWrite = false;
  int credentialReads = 0;
  Completer<RemoteSpeechSettings>? pendingRead;
  final readbackEntered = Completer<void>();
  @override
  Future<RemoteSpeechSettings> read() async {
    if (failAfterWrite) throw StateError('fixture readback failure');
    if (pendingRead != null) {
      if (!readbackEntered.isCompleted) readbackEntered.complete();
      return pendingRead!.future;
    }
    return data;
  }

  @override
  Future<RemoteSpeechCredentials> readCredentials() async {
    credentialReads++;
    return RemoteSpeechCredentials(data, key);
  }

  @override
  Future<void> save({
    required String name,
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    data = RemoteSpeechSettings(
      name: name,
      endpoint: endpoint,
      model: model,
      hasApiKey: true,
      selected: data.selected,
    );
    if (apiKey != null) key = apiKey;
    if (failAfterWrite) throw StateError('fixture write failure');
  }

  @override
  Future<void> select(bool remote) async {
    data = RemoteSpeechSettings(
      name: data.name,
      endpoint: data.endpoint,
      model: data.model,
      hasApiKey: data.hasApiKey,
      selected: remote,
    );
  }

  @override
  Future<void> clear() async {
    data = const RemoteSpeechSettings();
    key = '';
  }
}

Future<void> main() async {
  for (final entry in speechChecks().entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
