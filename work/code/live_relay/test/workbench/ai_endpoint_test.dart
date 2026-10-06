import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ai/ai_service_endpoint.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/ai_provider_settings_store.dart';
import 'package:live_relay/infrastructure/ai/http_conversation_provider.dart';
import 'package:live_relay/infrastructure/ai/openai_compatible_provider.dart';
import 'package:live_relay/infrastructure/ai/responses_agent_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('base and conventional API routes resolve on the selected host; custom routes stay exact', () {
    for (final value in [
      'https://api.deepseek.com',
      'https://api.deepseek.com/',
      'https://api.deepseek.com/responses',
      'https://api.deepseek.com/chat/completions/',
    ]) {
      expect(
        resolveAiEndpoint(Uri.parse(value), AiProtocol.responses).toString(),
        'https://api.deepseek.com/responses',
      );
    }
    expect(
      resolveAiEndpoint(
        Uri.parse('https://service.invalid:8443/v1/'),
        AiProtocol.responses,
      ).toString(),
      'https://service.invalid:8443/v1/responses',
    );
    expect(
      resolveAiEndpoint(
        Uri.parse('https://service.invalid/v1/responses?region=test'),
        AiProtocol.chatCompletions,
      ).toString(),
      'https://service.invalid/v1/chat/completions?region=test',
    );
    final custom = Uri.parse('https://custom.invalid/inference/run/?version=2');
    expect(resolveAiEndpoint(custom, AiProtocol.responses), custom);
  });

  test('saved and legacy base addresses resolve without changing or printing credentials', () async {
    FlutterSecureStorage.setMockInitialValues({
      'endpoint': 'https://api.deepseek.com',
      'model': 'deepseek-flash',
      'protocol': 'responses',
      'api-key': 'fixture-key',
    });
    final store = AiProviderSettingsStore();
    expect((await store.read()).endpoint, 'https://api.deepseek.com/responses');
    expect(await store.readApiKey(), 'fixture-key');
    await store.saveProfile(
      name: 'fixture',
      endpoint: 'https://selected.invalid/v1/',
      model: 'fixture-model',
      models: [],
      protocol: AiProtocol.responses,
      images: false,
      files: false,
    );
    expect(
      (await store.read()).endpoint,
      'https://selected.invalid/v1/responses',
    );
    await store.saveProtocol(AiProtocol.chatCompletions);
    expect(
      (await store.read()).endpoint,
      'https://selected.invalid/v1/chat/completions',
    );
    expect(await store.readApiKey(), 'fixture-key');
  });

  test(
    'all HTTP adapters resolve base URLs without redirects or extra requests',
    () async {
      final seen = <Uri>[];
      final client = MockClient((request) async {
        seen.add(request.url);
        expect(request.followRedirects, false);
        expect(request.headers['authorization'], 'Bearer fixture-key');
        final body = jsonDecode(request.body) as Map;
        if (request.url.path.endsWith('/responses')) {
          expect(body['store'], false);
          return http.Response(
            jsonEncode({
              'status': 'completed',
              'output': [
                {
                  'type': 'message',
                  'role': 'assistant',
                  'content': [
                    {
                      'type': 'output_text',
                      'text': '{"reply":"fixture","cards":[]}',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"cards":[]}'},
              },
            ],
          }),
          200,
        );
      });
      AiProviderRequest request(AiProtocol protocol) => AiProviderRequest(
        endpoint: Uri.parse('https://selected.invalid/v1'),
        apiKey: 'fixture-key',
        model: 'fixture-model',
        redactedText: 'fixture only',
        protocol: protocol,
      );
      await HttpConversationProvider(client: client)
          .converse(request(AiProtocol.responses), []);
      await ResponsesAgentProvider(client: client)
          .organize(request(AiProtocol.responses));
      await OpenAiCompatibleProvider(client: client)
          .organize(request(AiProtocol.chatCompletions));
      expect(seen.map((uri) => uri.path), [
        '/v1/responses',
        '/v1/responses',
        '/v1/chat/completions',
      ]);
      expect(seen.every((uri) => uri.host == 'selected.invalid'), true);
      client.close();
    },
  );

  test('404 gives a fixed diagnostic without echoing data or retrying another protocol', () async {
    var count = 0;
    final client = MockClient((request) async {
      count++;
      return http.Response('{"message":"fixture-key and private-input"}', 404);
    });
    await expectLater(
      HttpConversationProvider(client: client).converse(
        AiProviderRequest(
          endpoint: Uri.parse('https://custom.invalid/full-route'),
          apiKey: 'fixture-key',
          model: 'fixture',
          redactedText: 'private-input',
          protocol: AiProtocol.responses,
        ),
        [],
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'fixed diagnostic',
          '对话请求失败（HTTP 404）；请核对实际请求地址、所选协议和模型名。',
        ),
      ),
    );
    expect(count, 1);
    client.close();
  });
}
