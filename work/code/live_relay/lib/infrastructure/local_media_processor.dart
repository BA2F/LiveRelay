import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../application/preview_session.dart';
import 'private_cache.dart';

/// Bounded, offline Linux conversion. No user paths or URLs reach FFmpeg;
/// it only reads a private copy of the selected, signature-checked media.
class LocalMediaProcessor {
  LocalMediaProcessor(this.session, {bool Function()? active, this.cacheRoot})
    : _active = active ?? (() => true);
  final PreviewSession session;
  final bool Function() _active;
  final Future<Directory> Function()? cacheRoot;
  final _jobs = <_MediaJob>{};
  bool _closed = false;

  bool get active => !_closed && session.isUnlocked && _active();
  Future<void> close() async {
    _closed = true;
    await Future.wait([for (final job in List.of(_jobs)) job.cancel()]);
  }

  Future<T> _withInput<T>(
    Uint8List bytes,
    Future<T> Function(_MediaJob job, File input) operation,
  ) async {
    if (!Platform.isLinux) throw const FormatException('当前平台尚未支持音频格式转换');
    if (!active) throw const FormatException('媒体操作已取消');
    if (bytes.isEmpty || bytes.length > 8 * 1024 * 1024) {
      throw const FormatException('媒体处理每次最多8 MB');
    }
    final signature = bytes.length >= 12
        ? ascii.decode(bytes.sublist(4, 8), allowInvalid: true)
        : '';
    final accepted =
        signature == 'ftyp' ||
        (bytes.length >= 12 &&
            ascii.decode(bytes.sublist(0, 4), allowInvalid: true) == 'RIFF' &&
            ascii.decode(bytes.sublist(8, 12), allowInvalid: true) == 'WAVE') ||
        (bytes.length >= 3 &&
            ascii.decode(bytes.sublist(0, 3), allowInvalid: true) == 'ID3') ||
        (bytes.length >= 2 && bytes[0] == 255 && (bytes[1] & 224) == 224) ||
        (bytes.length >= 4 &&
            bytes[0] == 26 &&
            bytes[1] == 69 &&
            bytes[2] == 223 &&
            bytes[3] == 163);
    if (!accepted) throw const FormatException('请选择WAV、MP3、M4A、MP4或WebM媒体');
    final job = _MediaJob(() => active);
    _jobs.add(job);
    session.registerPreviewCleanup(job.cancel);
    Directory? directory;
    final owned = Uint8List.fromList(bytes);
    T? result;
    try {
      final root = await (cacheRoot?.call() ?? privateCacheDirectory());
      job.check();
      directory = await root.createTemp('media-');
      final file = File('${directory.path}/input.media');
      await file.writeAsBytes(owned, flush: true);
      job.check();
      result = await operation(job, file);
      job.check();
    } on ProcessException {
      throw const FormatException('本机需要FFmpeg和FFprobe才能转换媒体');
    } finally {
      owned.fillRange(0, owned.length, 0);
      try {
        if (directory != null && await directory.exists()) {
          await directory.delete(recursive: true);
        }
        job.check();
      } on Object {
        if (result is Uint8List) result.fillRange(0, result.length, 0);
        if (result is List<({int milliseconds, Uint8List bytes})>) {
          for (final frame in result) {
            frame.bytes.fillRange(0, frame.bytes.length, 0);
          }
        }
        rethrow;
      } finally {
        _jobs.remove(job);
        job.finish();
        session.unregisterPreviewCleanup(job.cancel);
      }
    }
    return result as T;
  }

  static const _inputOptions = [
    '-protocol_whitelist',
    'file',
    '-format_whitelist',
    'wav,mp3,mov,matroska,webm',
    '-max_alloc',
    '67108864',
  ];
  Future<({double seconds, double videoEnd, bool audio, bool video})> _probe(
    _MediaJob job,
    File input,
  ) async {
    final bytes = await job.run('ffprobe', [
      '-v',
      'error',
      ..._inputOptions,
      '-show_entries',
      'format=duration:stream=codec_type,width,height,duration,avg_frame_rate',
      '-of',
      'json',
      input.path,
    ], 32 * 1024);
    try {
      final data = jsonDecode(utf8.decode(bytes)) as Map;
      final seconds = double.tryParse(
        data['format']?['duration']?.toString() ?? '',
      );
      if (seconds == null || !seconds.isFinite || seconds <= 0) {
        throw const FormatException('无法核对媒体时长');
      }
      final streams = (data['streams'] as List? ?? []).cast<Map>();
      if (streams.length > 16 ||
          streams.any(
            (s) =>
                (s['width'] as num? ?? 0) > 4096 ||
                (s['height'] as num? ?? 0) > 4096,
          )) {
        throw const FormatException('媒体尺寸或轨道超过处理范围');
      }
      final video = streams
          .where((s) => s['codec_type'] == 'video')
          .firstOrNull;
      final rate = (video?['avg_frame_rate']?.toString() ?? '').split('/');
      final fps = rate.length == 2
          ? (double.tryParse(rate[0]) ?? 0) / (double.tryParse(rate[1]) ?? 0)
          : 0.0;
      final duration =
          double.tryParse(video?['duration']?.toString() ?? '') ?? seconds;
      final end = fps.isFinite && fps > 0
          ? (duration - 1 / fps).clamp(0.0, seconds).toDouble()
          : seconds * 0.9;
      return (
        seconds: seconds,
        videoEnd: end,
        audio: streams.any((s) => s['codec_type'] == 'audio'),
        video: streams.any((s) => s['codec_type'] == 'video'),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Uint8List> normalizeAudio(Uint8List bytes) => _withInput(bytes, (
    job,
    input,
  ) async {
    final info = await _probe(job, input);
    if (!info.audio) throw const FormatException('这个文件没有音轨');
    if (info.seconds > 60) throw const FormatException('完整音频转换限60秒，请先选择较短资料');
    final pcm = await job.run('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      ..._inputOptions,
      '-threads',
      '1',
      '-i',
      input.path,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-threads',
      '1',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-c:a',
      'pcm_s16le',
      '-f',
      's16le',
      'pipe:1',
    ], 16000 * 2 * 60);
    try {
      if (pcm.isEmpty || pcm.length.isOdd) {
        throw const FormatException('音轨无法转换为PCM');
      }
      final wav = Uint8List(44 + pcm.length);
      wav.setRange(0, 4, ascii.encode('RIFF'));
      wav.setRange(8, 12, ascii.encode('WAVE'));
      wav.setRange(12, 16, ascii.encode('fmt '));
      wav.setRange(36, 40, ascii.encode('data'));
      final d = ByteData.sublistView(wav);
      d.setUint32(4, wav.length - 8, Endian.little);
      d.setUint32(16, 16, Endian.little);
      d.setUint16(20, 1, Endian.little);
      d.setUint16(22, 1, Endian.little);
      d.setUint32(24, 16000, Endian.little);
      d.setUint32(28, 32000, Endian.little);
      d.setUint16(32, 2, Endian.little);
      d.setUint16(34, 16, Endian.little);
      d.setUint32(40, pcm.length, Endian.little);
      wav.setRange(44, wav.length, pcm);
      job.check();
      return wav;
    } finally {
      pcm.fillRange(0, pcm.length, 0);
    }
  });

  Future<List<({int milliseconds, Uint8List bytes})>> sampleFrames(
    Uint8List bytes,
  ) => _withInput(bytes, (job, input) async {
    final info = await _probe(job, input);
    if (!info.video || info.seconds > 600) {
      throw const FormatException('选帧需要10分钟以内的视频');
    }
    final frames = <({int milliseconds, Uint8List bytes})>[];
    try {
      for (final fraction in [0.05, 0.35, 0.65, 0.95]) {
        final seconds = (info.seconds * fraction)
            .clamp(0.0, info.videoEnd)
            .toDouble();
        final frame = await job.run('ffmpeg', [
          '-nostdin',
          '-v',
          'error',
          ..._inputOptions,
          '-threads',
          '1',
          '-ss',
          seconds.toStringAsFixed(3),
          '-i',
          input.path,
          '-map',
          '0:v:0',
          '-an',
          '-sn',
          '-dn',
          '-frames:v',
          '1',
          '-threads',
          '1',
          '-filter_threads',
          '1',
          '-vf',
          'scale=640:640:force_original_aspect_ratio=decrease',
          '-pix_fmt',
          'yuvj420p',
          '-c:v',
          'mjpeg',
          '-q:v',
          '5',
          '-f',
          'image2pipe',
          'pipe:1',
        ], 256 * 1024);
        if (frame.length < 3 ||
            frame[0] != 255 ||
            frame[1] != 216 ||
            frame[2] != 255) {
          frame.fillRange(0, frame.length, 0);
          throw const FormatException('视频帧无法生成');
        }
        frames.add((milliseconds: (seconds * 1000).round(), bytes: frame));
      }
      job.check();
      return frames;
    } on Object {
      for (final frame in frames) {
        frame.bytes.fillRange(0, frame.bytes.length, 0);
      }
      rethrow;
    }
  });
}

class _MediaJob {
  _MediaJob(this.active);
  final bool Function() active;
  final _finished = Completer<void>();
  bool _cancelled = false;
  Process? _process;
  void check() {
    if (_cancelled || !active()) throw const FormatException('媒体操作已取消');
  }

  Future<void> cancel() {
    _cancelled = true;
    _process?.kill(ProcessSignal.sigkill);
    return _finished.future;
  }

  void finish() {
    if (!_finished.isCompleted) _finished.complete();
  }

  Future<Uint8List> run(
    String executable,
    List<String> args,
    int maxOutput,
  ) async {
    check();
    final process = await Process.start(executable, args, runInShell: false);
    _process = process;
    final buffer = Uint8List(maxOutput);
    var count = 0, exceeded = false, timedOut = false;
    final timer = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      process.kill(ProcessSignal.sigkill);
    });
    final watcher = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (_cancelled || !active()) process.kill(ProcessSignal.sigkill);
    });
    try {
      final stdout = process.stdout.listen((chunk) {
        if (count + chunk.length > buffer.length) {
          exceeded = true;
          process.kill(ProcessSignal.sigkill);
        } else {
          buffer.setRange(count, count + chunk.length, chunk);
          count += chunk.length;
        }
        chunk.fillRange(0, chunk.length, 0);
      }).asFuture<void>();
      final stderr = process.stderr.listen((chunk) {
        chunk.fillRange(0, chunk.length, 0);
      }).asFuture<void>();
      final code = await process.exitCode;
      await Future.wait([stdout, stderr]);
      check();
      if (exceeded || timedOut || code != 0) {
        throw const FormatException('媒体转换失败或超过时长/大小限制');
      }
      final result = Uint8List(count)..setRange(0, count, buffer);
      return result;
    } finally {
      timer.cancel();
      watcher.cancel();
      buffer.fillRange(0, buffer.length, 0);
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      _process = null;
    }
  }
}
