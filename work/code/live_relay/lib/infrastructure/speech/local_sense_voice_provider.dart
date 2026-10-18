import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart' as archive;
import 'package:http/http.dart' as http;
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../core/ports/speech_provider.dart';
import '../../core/storage/file_commit.dart';
import 'pcm_wave.dart';

class LocalSenseVoiceProvider implements SpeechProvider {
  LocalSenseVoiceProvider(this.resolveDirectory);
  final Future<Directory> Function() resolveDirectory;
  static const modelName =
      'sherpa-onnx-sense-voice-zh-en-ja-ko-yue-int8-2024-07-17';
  static const modelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/$modelName.tar.bz2';
  static const maximumArchiveBytes = 320 * 1024 * 1024;
  http.Client? _downloadClient;
  int _generation = 0;

  Future<Directory> get _installed async =>
      Directory('${(await resolveDirectory()).path}/$modelName');

  @override
  Future<bool> isModelInstalled() async {
    final dir = await _installed;
    final model = File('${dir.path}/model.int8.onnx');
    final tokens = File('${dir.path}/tokens.txt');
    final marker = File('${dir.path}/installed.json');
    if (!await model.exists() ||
        !await tokens.exists() ||
        !await marker.exists()) {
      return false;
    }
    try {
      final info = jsonDecode(await marker.readAsString()) as Map;
      return info['model'] == modelName &&
          info['modelBytes'] == await model.length() &&
          info['tokensBytes'] == await tokens.length();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> downloadModel(SpeechDownloadProgress progress) async {
    if (_downloadClient != null) throw StateError('模型下载正在进行');
    final generation = _generation;
    final client = http.Client();
    _downloadClient = client;
    Directory? scratch;
    IOSink? sink;
    try {
      final root = await resolveDirectory();
      await root.create(recursive: true);
      scratch = await root.createTemp('download-');
      final file = File('${scratch.path}/model.tar.bz2');
      var uri = Uri.parse(modelUrl);
      http.StreamedResponse? response;
      for (var redirects = 0; redirects < 5; redirects++) {
        if (uri.scheme != 'https' ||
            !{
              'github.com',
              'release-assets.githubusercontent.com',
              'objects.githubusercontent.com',
            }.contains(uri.host)) {
          throw const FormatException('模型下载地址不受支持');
        }
        final request = http.Request('GET', uri)..followRedirects = false;
        final next = await client
            .send(request)
            .timeout(const Duration(seconds: 45));
        if (next.isRedirect) {
          final location = next.headers['location'];
          // Cancel the redirect body without accumulating it.
          final subscription = next.stream.listen((_) {});
          await subscription.cancel();
          if (location == null) throw const FormatException('模型下载地址无效');
          uri = uri.resolve(location);
          continue;
        }
        response = next;
        break;
      }
      if (response == null ||
          response.statusCode != 200 ||
          (response.contentLength ?? 0) > maximumArchiveBytes) {
        throw const FormatException('模型下载失败，请稍后重试或导入模型包');
      }
      sink = file.openWrite();
      var received = 0;
      await for (final bytes in response.stream.timeout(
        const Duration(seconds: 45),
      )) {
        if (generation != _generation) throw const FormatException('已取消模型下载');
        received += bytes.length;
        if (received > maximumArchiveBytes) {
          throw const FormatException('模型包超出大小限制');
        }
        sink.add(bytes);
        progress(received, response.contentLength);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (generation != _generation) throw const FormatException('已取消模型下载');
      await installArchive(file.path);
    } finally {
      await sink?.close();
      client.close();
      _downloadClient = null;
      if (scratch != null && await scratch.exists()) {
        await scratch.delete(recursive: true);
      }
    }
  }

  @override
  Future<void> installArchive(String path) async {
    if (await isModelInstalled()) throw StateError('本地模型已安装，请先移除旧模型');
    final generation = _generation;
    final source = File(path);
    if (!await source.exists() || await source.length() > maximumArchiveBytes) {
      throw const FormatException('模型包不存在或过大');
    }
    final root = await resolveDirectory();
    await root.create(recursive: true);
    final staging = await root.createTemp('install-');
    final stagePath = staging.path;
    try {
      await Isolate.run(() => extractSenseVoiceArchive(path, stagePath));
      if (generation != _generation) throw const FormatException('已取消模型安装');
      final target = await _installed;
      if (await target.exists()) await target.delete(recursive: true);
      await commitDirectory(staging, target);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }

  @override
  Future<void> cancelDownload() async {
    _generation++;
    _downloadClient?.close();
  }

  @override
  Future<void> removeModel() async {
    final dir = await _installed;
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  @override
  Future<String> transcribe(Uint8List wav) async {
    if (!await isModelInstalled()) throw StateError('请先安装本地语音模型');
    // Reject oversized/malformed audio before crossing the isolate boundary.
    final check = PcmWave.decode(wav);
    check.fillRange(0, check.length, 0);
    final directory = (await _installed).path;
    final copy = Uint8List.fromList(wav);
    try {
      return await Isolate.run(() => recognizeSenseVoice(directory, copy));
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }
}

/// Unpacks only two known files into an isolated staging directory. Entry paths
/// are never used as filesystem destinations, and links are never extracted.
void extractSenseVoiceArchive(String path, String destination) {
  final tarPath = '$destination/unpacked.tar';
  final compressed = archive.InputFileStream(path);
  final output = _BoundedFileOutput(tarPath, 512 * 1024 * 1024);
  try {
    archive.BZip2Decoder().decodeStream(compressed, output, verify: true);
  } finally {
    compressed.closeSync();
    output.closeSync();
  }
  final input = archive.InputFileStream(tarPath);
  try {
    final contents = archive.TarDecoder().decodeStream(input, verify: true);
    if (contents.length > 200) throw const FormatException('模型包文件数量异常');
    final seen = <String>{};
    for (final entry in contents) {
      final name = entry.name.split('/').last;
      if (!{'model.int8.onnx', 'tokens.txt'}.contains(name)) continue;
      if (!entry.isFile ||
          entry.isSymbolicLink ||
          !seen.add(name) ||
          entry.size <= 0 ||
          entry.size >
              (name == 'tokens.txt' ? 4 * 1024 * 1024 : 300 * 1024 * 1024)) {
        throw const FormatException('模型包内容无效');
      }
      final file = archive.OutputFileStream('$destination/$name');
      try {
        entry.writeContent(file);
      } finally {
        file.closeSync();
      }
    }
    if (seen.length != 2) throw const FormatException('模型包缺少 INT8 模型或词表');
    final model = File('$destination/model.int8.onnx');
    final tokens = File('$destination/tokens.txt');
    if (model.lengthSync() < 1024 * 1024) {
      throw const FormatException('模型文件不完整');
    }
    File('$destination/installed.json').writeAsStringSync(
      jsonEncode({
        'model': LocalSenseVoiceProvider.modelName,
        'modelBytes': model.lengthSync(),
        'tokensBytes': tokens.lengthSync(),
      }),
      flush: true,
    );
  } finally {
    input.closeSync();
    File(tarPath).deleteSync();
  }
}

String recognizeSenseVoice(String directory, Uint8List wav) {
  final samples = PcmWave.decode(wav);
  sherpa.OfflineRecognizer? recognizer;
  sherpa.OfflineStream? stream;
  try {
    sherpa.initBindings();
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          senseVoice: sherpa.OfflineSenseVoiceModelConfig(
            model: '$directory/model.int8.onnx',
            language: 'auto',
            useInverseTextNormalization: true,
          ),
          tokens: '$directory/tokens.txt',
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
      ),
    );
    stream = recognizer.createStream();
    stream.acceptWaveform(samples: samples, sampleRate: 16000);
    recognizer.decode(stream);
    final text = recognizer.getResult(stream).text.trim();
    if (text.isEmpty) throw const FormatException('没有识别到语音，请重试');
    return text;
  } finally {
    stream?.free();
    recognizer?.free();
    samples.fillRange(0, samples.length, 0);
    wav.fillRange(0, wav.length, 0);
  }
}

class _BoundedFileOutput extends archive.OutputStream {
  _BoundedFileOutput(String path, this.limit)
    : _file = archive.OutputFileStream(path),
      super(byteOrder: archive.ByteOrder.littleEndian);
  final archive.OutputFileStream _file;
  final int limit;
  void _check(int n) {
    if (length + n > limit) throw const FormatException('模型解压内容过大');
  }

  @override
  int get length => _file.length;
  @override
  void writeByte(int value) {
    _check(1);
    _file.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    _file.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(archive.InputStream stream) {
    _check(stream.length);
    _file.writeStream(stream);
  }

  @override
  void flush() => _file.flush();
  @override
  void clear() => _file.clear();
  @override
  Uint8List subset(int start, [int? end]) => _file.subset(start, end);
  @override
  void closeSync() => _file.closeSync();
}
