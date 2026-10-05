import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/http_conversation_provider.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';
import 'package:live_relay/core/domain/entities.dart';

void main() {
  test('Responses replays output and encrypted reasoning without storing upstream state', () async {
    final history = <Map<String, Object?>>[
      {'role': 'user', 'content': 'first'},
      {'type': 'reasoning', 'encrypted_content': 'opaque'},
      {
        'type': 'message',
        'role': 'assistant',
        'content': [
          {'type': 'output_text', 'text': 'first reply'},
        ],
      },
    ];
    final provider = HttpConversationProvider(
      client: MockClient((request) async {
        final data = jsonDecode(request.body);
        expect(data['store'], false);
        expect(data['include'], contains('reasoning.encrypted_content'));
        expect(data['input'].take(3).toList(), history);
        expect(data['input'].last['content'], 'second');
        expect(data.containsKey('tools'), false);
        return http.Response(
          jsonEncode({
            'status': 'completed',
            'output': [
              {
                'type': 'message',
                'role': 'assistant',
                'content': [
                  {'type': 'output_text', 'text': '{"reply":"ok","cards":[]}'},
                ],
              },
            ],
          }),
          200,
        );
      }),
    );
    final result = await provider.converse(
      AiProviderRequest(
        endpoint: Uri.parse('https://fixture.invalid/v1/responses'),
        apiKey: 'fixture',
        model: 'fixture',
        redactedText: 'second',
        protocol: AiProtocol.responses,
      ),
      history,
    );
    expect(jsonDecode(result.content)['reply'], 'ok');
    expect(result.output.single['type'], 'message');
  });
  test('Chat Completions includes history and rejects external tools, errors and insecure endpoints', () async {
    final provider = HttpConversationProvider(
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['store'], false);
        expect(body['messages'].length, 3);
        return http.Response(
          jsonEncode({
            'choices': [
              {
                'message': {'content': '{"reply":"ok","cards":[]}'},
              },
            ],
          }),
          200,
        );
      }),
    );
    final request = AiProviderRequest(
      endpoint: Uri.parse('https://fixture.invalid/chat'),
      apiKey: 'fixture',
      model: 'fixture',
      redactedText: 'next',
    );
    expect(
      (await provider.converse(request, [
        {'role': 'assistant', 'content': 'prior'},
      ])).output.single['role'],
      'assistant',
    );
    await expectLater(
      provider.converse(
        AiProviderRequest(
          endpoint: Uri.parse('http://fixture.invalid'),
          apiKey: 'fixture',
          model: 'fixture',
          redactedText: 'next',
        ),
        [],
      ),
      throwsFormatException,
    );
    final forbidden = HttpConversationProvider(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'output': [
              {'type': 'function_call', 'name': 'read_vault'},
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      forbidden.converse(
        AiProviderRequest(
          endpoint: request.endpoint,
          apiKey: 'fixture',
          model: 'fixture',
          redactedText: 'next',
          protocol: AiProtocol.responses,
        ),
        [],
      ),
      throwsFormatException,
    );
  });
  test('review receipts make confirmation atomic and idempotent while release stays hidden', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      const drafts = [CardDraft(title: '本人修改', content: '明确确认的内容')];
      final first = await r.saveReviewedAgentSuggestions(
        'fixture-review',
        'source',
        drafts,
        providerLabel: 'fixture',
      );
      final second = await r.saveReviewedAgentSuggestions(
        'fixture-review',
        'source',
        drafts,
        providerLabel: 'fixture',
      );
      expect(first.single.id, second.single.id);
      expect((await r.listCards()).length, 1);
      expect(first.single.status, CardStatus.confirmed);
      expect(
        (await r.getReleasePolicy(
          'card',
          first.single.id,
        )).visibleAt(LifeState.deceased),
        VisibilityLevel.hidden,
      );
      await expectLater(
        r.saveReviewedAgentSuggestions('invalid-batch', 'source', [
          drafts.single,
          const CardDraft(title: '', content: 'bad'),
        ], providerLabel: 'fixture'),
        throwsFormatException,
      );
      expect((await r.listCards()).length, 1);
      expect(await r.readLocalValue('agent.review.invalid-batch'), isNull);
    } finally {
      await r.close();
    }
  });
}
