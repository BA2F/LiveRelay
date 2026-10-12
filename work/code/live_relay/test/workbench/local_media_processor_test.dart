import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/preview_session.dart';
import 'package:live_relay/infrastructure/local_media_processor.dart';
import 'package:live_relay/infrastructure/speech/pcm_wave.dart';

import 'remote_speech_test.dart' show wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('real offline M4A and MP4 conversions keep complete audio, bounded frames and remove private copies', () async {
    final root = await Directory.systemTemp.createTemp(
      'liverelay-media-convert-',
    );
    final session = _TestPreviewSession();
    final processor = LocalMediaProcessor(session, cacheRoot: () async => root);
    try {
      final wav = await File('${root.path}/fixture.wav').writeAsBytes(wave());
      final m4a = File('${root.path}/fixture.m4a');
      expect(
        (await Process.run('ffmpeg', [
          '-v',
          'error',
          '-i',
          wav.path,
          '-c:a',
          'aac',
          m4a.path,
        ])).exitCode,
        0,
      );
      final video = File('${root.path}/fixture.mp4');
      expect(
        (await Process.run('ffmpeg', [
          '-v',
          'error',
          '-f',
          'lavfi',
          '-i',
          'color=c=blue:s=160x90:r=25:d=0.5',
          '-i',
          wav.path,
          '-c:v',
          'mpeg4',
          '-c:a',
          'aac',
          '-shortest',
          video.path,
        ])).exitCode,
        0,
      );
      final raw = await m4a.readAsBytes();
      final normalized = await processor.normalizeAudio(raw);
      final samples = PcmWave.decode(normalized);
      expect(samples.length, greaterThanOrEqualTo(1600));
      normalized.fillRange(0, normalized.length, 0);
      samples.fillRange(0, samples.length, 0);
      expect(raw, await m4a.readAsBytes());
      final videoBytes = await video.readAsBytes();
      final track = await processor.normalizeAudio(videoBytes);
      expect(PcmWave.decode(track), isNotEmpty);
      track.fillRange(0, track.length, 0);
      final frames = await processor.sampleFrames(videoBytes);
      expect(frames, hasLength(4));
      expect(
        frames.map((f) => f.milliseconds).toList(),
        orderedEquals([...frames.map((f) => f.milliseconds)]..sort()),
      );
      for (final f in frames) {
        expect(f.bytes.length, lessThanOrEqualTo(256 * 1024));
        f.bytes.fillRange(0, f.bytes.length, 0);
      }
      expect((await root.list().toList()).whereType<Directory>(), isEmpty);
      final long = Uint8List(44 + 16000 * 2 * 61)..setRange(0, 44, wave());
      ByteData.sublistView(long).setUint32(4, long.length - 8, Endian.little);
      ByteData.sublistView(long).setUint32(40, long.length - 44, Endian.little);
      await expectLater(processor.normalizeAudio(long), throwsFormatException);
      await expectLater(
        processor.normalizeAudio(
          Uint8List.fromList('file:///private'.codeUnits),
        ),
        throwsFormatException,
      );
      expect((await root.list().toList()).whereType<Directory>(), isEmpty);
    } finally {
      await processor.close();
      await session.revoke();
      session.dispose();
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
  test('revocation waits for a late cache allocation and removes the owned working copy', () async {
    final root = await Directory.systemTemp.createTemp('liverelay-media-late-');
    final session = _TestPreviewSession();
    final gate = Completer<Directory>();
    final processor = LocalMediaProcessor(
      session,
      cacheRoot: () => gate.future,
    );
    try {
      final input = wave();
      final work = processor.normalizeAudio(input);
      final rejected = expectLater(work, throwsFormatException);
      var cleaned = false;
      final cleanup = session.revoke().then((_) => cleaned = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleaned, false);
      gate.complete(root);
      await rejected;
      await cleanup;
      expect(await root.list().toList(), isEmpty);
      expect(input, wave());
    } finally {
      if (!gate.isCompleted) gate.complete(root);
      await processor.close();
      session.dispose();
      await root.delete(recursive: true);
    }
  }, skip: !Platform.isLinux);
}

class _TestPreviewSession extends ChangeNotifier implements PreviewSession {
  bool _unlocked = true;
  final _cleanups = <Future<void> Function()>{};
  @override
  bool get isUnlocked => _unlocked;
  @override
  void registerPreviewCleanup(Future<void> Function() cleanup) =>
      _cleanups.add(cleanup);
  @override
  void unregisterPreviewCleanup(Future<void> Function() cleanup) =>
      _cleanups.remove(cleanup);
  Future<void> revoke() async {
    _unlocked = false;
    notifyListeners();
    await Future.wait([for (final cleanup in List.of(_cleanups)) cleanup()]);
  }
}
