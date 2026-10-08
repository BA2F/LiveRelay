import 'package:live_relay/infrastructure/app_composition.dart';

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/speech_provider.dart';
import 'package:live_relay/core/ports/remote_speech_provider.dart';
import 'package:live_relay/infrastructure/speech/http_remote_speech_provider.dart';

Uint8List wave() {
  final b = Uint8List(44 + 3200);
  b.setRange(0, 4, ascii.encode('RIFF'));
  b.setRange(8, 12, ascii.encode('WAVE'));
  b.setRange(12, 16, ascii.encode('fmt '));
  b.setRange(36, 40, ascii.encode('data'));
  final d = ByteData.sublistView(b);
  d.setUint32(4, b.length - 8, Endian.little);
  d.setUint32(16, 16, Endian.little);
  d.setUint16(20, 1, Endian.little);
  d.setUint16(22, 1, Endian.little);
  d.setUint32(24, 16000, Endian.little);
  d.setUint32(28, 32000, Endian.little);
  d.setUint16(32, 2, Endian.little);
  d.setUint16(34, 16, Endian.little);
  d.setUint32(40, 3200, Endian.little);
  return b;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('remote adapter sends an explicit bounded WAV multipart and validates text; redirects and invalid files are rejected', () async {
    var calls = 0;
    var status = 200;
    final provider = HttpRemoteSpeechProvider(
      client: MockClient((request) async {
        calls++;
        expect(
          request.url.toString(),
          'https://asr.invalid/audio/transcriptions',
        );
        expect(request.headers['authorization'], 'Bearer fixture-only-key');
        expect(request.followRedirects, false);
        expect(
          request.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        final body = utf8.decode(request.bodyBytes, allowMalformed: true);
        expect(body, contains('name="file"; filename="audio.wav"'));
        expect(body, contains('name="model"'));
        expect(body, contains('fixture-asr-model'));
        expect(body, contains('name="response_format"'));
        expect(body, contains('json'));
        return http.Response(
          '{"text":"虚构转写结果"}',
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
    RemoteSpeechRequest request(Uint8List wav) => RemoteSpeechRequest(
      endpoint: Uri.parse('https://asr.invalid/audio/transcriptions'),
      apiKey: 'fixture-only-key',
      model: 'fixture-asr-model',
      wav: wav,
      cancellation: AiCancellation(),
    );
    expect(await provider.transcribe(request(wave())), '虚构转写结果');
    status = 302;
    await expectLater(
      provider.transcribe(request(wave())),
      throwsFormatException,
    );
    await expectLater(
      provider.transcribe(request(Uint8List.fromList([1, 2, 3]))),
      throwsFormatException,
    );
    expect(calls, 2);
    provider.close();
  });
  test('local default never uploads, remote requires current one-time confirmation, cancellation discards late text and wipes audio', () async {
    final local = _Local();
    final remote = _Remote();
    final service = createSpeechService(
      local,
      supported: true,
      remoteProvider: remote,
    );
    try {
      await service.refresh();
      await service.configureRemote(
        name: 'fixture speech',
        endpoint: 'https://asr.invalid/audio',
        model: 'fixture-model',
        apiKey: 'fixture-key',
      );
      expect(service.usingRemote, false);
      expect(await service.transcribe(wave()), 'local fixture');
      expect(remote.calls, 0);
      await service.chooseRemote(true);
      final rejectedAudio = wave();
      await expectLater(
        service.transcribe(rejectedAudio),
        throwsFormatException,
      );
      expect(rejectedAudio.every((v) => v == 0), true);
      expect(remote.calls, 0);
      final oldConsent = service.configurationGeneration;
      await service.configureRemote(
        name: 'changed',
        endpoint: 'https://other.invalid/audio',
        model: 'other',
      );
      await expectLater(
        service.transcribe(wave(), authorizedRemoteGeneration: oldConsent),
        throwsFormatException,
      );
      remote.delay = true;
      final bytes = wave();
      final work = service.transcribe(
        bytes,
        authorizedRemoteGeneration: service.configurationGeneration,
      );
      await remote.started.future;
      service.cancelTranscription();
      remote.release.complete();
      await expectLater(work, throwsFormatException);
      expect(bytes.every((v) => v == 0), true);
      expect(local.calls, 1);
    } finally {
      service.dispose();
    }
  });
}

class _Remote implements RemoteSpeechProvider {
  int calls = 0;
  bool delay = false;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<String> transcribe(RemoteSpeechRequest request) async {
    calls++;
    started.complete();
    if (delay) await release.future;
    return 'late remote fixture';
  }
}

class _Local implements SpeechProvider {
  int calls = 0;
  @override
  Future<bool> isModelInstalled() async => true;
  @override
  Future<void> downloadModel(SpeechDownloadProgress progress) async {}
  @override
  Future<void> installArchive(String path) async {}
  @override
  Future<void> removeModel() async {}
  @override
  Future<void> cancelDownload() async {}
  @override
  Future<String> transcribe(Uint8List wav) async {
    calls++;
    return 'local fixture';
  }
}
