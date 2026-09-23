import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/openai_compatible_provider.dart';

void main() {
  test(
    'sends only supplied redacted text and reads structured content',
    () async {
      late http.Request captured;
      final provider = OpenAiCompatibleProvider(
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"cards":[]}'},
                },
              ],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final result = await provider.organize(
        AiProviderRequest(
          endpoint: Uri.parse('https://provider.example/v1/chat/completions'),
          apiKey: 'test-key',
          model: 'test-model',
          redactedText: '[[SECRET_01]]\n可发送文本',
        ),
      );

      expect(result, '{"cards":[]}');
      expect(captured.followRedirects, isFalse);
      expect(captured.body, contains('[[SECRET_01]]'));
      expect(captured.body, isNot(contains('real-secret')));
    },
  );

  test('rejects non-HTTPS endpoints before making a request', () async {
    var called = false;
    final provider = OpenAiCompatibleProvider(
      client: MockClient((_) async {
        called = true;
        return http.Response('{}', 200);
      }),
    );

    await expectLater(
      provider.organize(
        AiProviderRequest(
          endpoint: Uri.parse('http://provider.example/v1/chat/completions'),
          apiKey: 'key',
          model: 'model',
          redactedText: 'safe',
        ),
      ),
      throwsA(isA<FormatException>()),
    );
    expect(called, isFalse);
  });
}
