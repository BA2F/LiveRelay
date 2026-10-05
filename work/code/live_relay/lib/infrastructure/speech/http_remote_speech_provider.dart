import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/ports/remote_speech_provider.dart';
import 'pcm_wave.dart';

class HttpRemoteSpeechProvider implements RemoteSpeechProvider {
  HttpRemoteSpeechProvider({http.Client? client})
    : _client = client ?? http.Client();
  final http.Client _client;
  void close() => _client.close();
  @override
  Future<String> transcribe(RemoteSpeechRequest request) async {
    if (request.endpoint.scheme != 'https' ||
        request.endpoint.host.isEmpty ||
        request.endpoint.userInfo.isNotEmpty ||
        request.apiKey.isEmpty ||
        request.model.isEmpty) {
      throw const FormatException('请配置 HTTPS 语音服务、密钥和模型');
    }
    final samples = PcmWave.decode(request.wav);
    samples.fillRange(0, samples.length, 0);
    request.cancellation.check();
    final message =
        http.AbortableMultipartRequest(
            'POST',
            request.endpoint,
            abortTrigger: request.cancellation.whenCancelled,
          )
          ..followRedirects = false
          ..headers['authorization'] = 'Bearer ${request.apiKey}'
          ..fields.addAll({'model': request.model, 'response_format': 'json'})
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              request.wav,
              filename: 'audio.wav',
            ),
          );
    try {
      final response = await _client
          .send(message)
          .timeout(const Duration(seconds: 60));
      if (response.isRedirect ||
          response.statusCode < 200 ||
          response.statusCode >= 300) {
        throw FormatException('语音识别失败（HTTP ${response.statusCode}）');
      }
      final bytes = <int>[];
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (bytes.length + chunk.length > 256 * 1024) {
          throw const FormatException('语音响应过大');
        }
        bytes.addAll(chunk);
      }
      request.cancellation.check();
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map ||
          decoded['text'] is! String ||
          (decoded['text'] as String).trim().isEmpty ||
          (decoded['text'] as String).length > 32000) {
        throw const FormatException('语音服务未返回有效文字');
      }
      return (decoded['text'] as String).trim();
    } on http.RequestAbortedException {
      throw const FormatException('已取消远程语音识别');
    } on TimeoutException {
      request.cancellation.cancel();
      throw const FormatException('远程语音识别超时，请重试');
    }
  }
}
