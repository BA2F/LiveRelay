import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/application/draft_agent_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/agent_command_provider.dart';
import 'package:live_relay/infrastructure/ai/responses_agent_provider.dart';

Map<String, Object?> call(String name, {String id = 'call_1', Object? args}) =>
    {
      'type': 'function_call',
      'call_id': id,
      'name': name,
      'arguments': jsonEncode(args ?? <String, Object?>{}),
    };
http.Response reply(List<Object?> output) => http.Response(
  jsonEncode({'status': 'completed', 'output': output}),
  200,
  headers: {'content-type': 'application/json'},
);
AiProviderRequest request({AiCancellation? cancellation}) => AiProviderRequest(
  endpoint: Uri.parse('https://provider.example/v1/responses'),
  apiKey: 'fictional-test-key',
  model: 'fictional-model',
  redactedText: '资料',
  protocol: AiProtocol.responses,
  cancellation: cancellation,
);

class FakeCommands implements AgentCommandProvider {
  String? input;
  final session = FakeCommandSession();
  @override
  Future<bool> available() async => true;
  @override
  Future<AgentCommandSession> open(
    String redactedText, {
    Future<void>? whenCancelled,
  }) async {
    input = redactedText;
    return session;
  }
}

class FakeCommandSession implements AgentCommandSession {
  bool closed = false;
  @override
  final history = <AgentCommandResult>[];
  @override
  Future<AgentCommandResult> run(String command) async {
    final result = AgentCommandResult(
      command: command,
      exitCode: 0,
      stdout: '[[SECRET_01]]',
      stderr: '',
    );
    history.add(result);
    return result;
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

void main() {
  test('explicit command consent passes only redacted input and closes the session', () async {
    final commands = FakeCommands();
    var turns = 0;
    final provider = ResponsesAgentProvider(
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map<String, dynamic>;
        expect(
          (body['tools'] as List).any((t) => t['name'] == 'run_command'),
          isTrue,
        );
        if (++turns == 1) {
          return reply([
            call('run_command', args: {'command': 'cat /input/input.txt'}),
          ]);
        }
        if (turns == 2) {
          return reply([
            call(
              'stage_card',
              id: 'call_2',
              args: {
                'title': '资料',
                'content': '[[SECRET_01]]',
                'kind': 'note',
                'inference': false,
              },
            ),
          ]);
        }
        return reply([]);
      }),
    );
    final batch = await DraftAgentService(provider, commands: commands).propose(
      text: 'fictional-secret-value',
      marks: const [
        SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.secret),
      ],
      endpoint: request().endpoint,
      model: 'fictional-model',
      apiKey: 'fictional-test-key',
      allowCommands: true,
    );
    expect(commands.input, '[[SECRET_01]]');
    expect(commands.session.closed, isTrue);
    expect(batch.commandHistory.single.command, 'cat /input/input.txt');
    expect(batch.suggestions.single.content, 'fictional-secret-value');
  });
  test(
    'stateless tool loop keeps secrets local and replays encrypted reasoning',
    () async {
      final bodies = <Map<String, dynamic>>[];
      final provider = ResponsesAgentProvider(
        client: MockClient((r) async {
          expect(r.followRedirects, isFalse);
          expect(r.body, isNot(contains('fictional-secret-value')));
          final body = jsonDecode(r.body) as Map<String, dynamic>;
          bodies.add(body);
          expect(body['store'], isFalse);
          expect(
            (body['tools'] as List).any((t) => t['name'] == 'run_command'),
            isFalse,
          );
          if (bodies.length == 1) {
            expect(body['input'].toString(), contains('[[SECRET_01]]'));
            return reply([
              {
                'type': 'reasoning',
                'id': 'rs_1',
                'summary': [],
                'encrypted_content': 'encrypted-test',
              },
              call(
                'stage_card',
                args: {
                  'title': '家庭资料',
                  'content': '[[SECRET_01]]',
                  'kind': 'note',
                  'inference': false,
                },
              ),
            ]);
          }
          final inputs = body['input'] as List;
          expect(
            inputs
                .where((i) => i['type'] == 'reasoning')
                .single['encrypted_content'],
            'encrypted-test',
          );
          final result = inputs
              .where((i) => i['type'] == 'function_call_output')
              .single;
          expect(result['call_id'], 'call_1');
          expect(jsonDecode(result['output'] as String)['saved'], isFalse);
          return reply([]);
        }),
      );
      final batch = await DraftAgentService(provider).propose(
        text: 'fictional-secret-value',
        marks: const [
          SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.secret),
        ],
        endpoint: request().endpoint,
        model: 'fictional-model',
        apiKey: 'fictional-test-key',
      );
      expect(bodies, hasLength(2));
      expect(batch.sourceText, 'fictional-secret-value');
      expect(batch.suggestions.single.content, 'fictional-secret-value');
      expect(batch.suggestions.single.toDraft().status, CardStatus.draft);
    },
  );

  test(
    'unknown tools and repeated call ids fail before another request',
    () async {
      for (final outputs in [
        [call('run_shell')],
        [
          call('run_command', args: {'command': 'cat /input/input.txt'}),
        ],
        [call('staged_count'), call('staged_count')],
      ]) {
        var calls = 0;
        final provider = ResponsesAgentProvider(
          client: MockClient((_) async {
            calls++;
            return reply(outputs);
          }),
        );
        await expectLater(
          provider.organize(request()),
          throwsA(isA<FormatException>()),
        );
        expect(calls, 1);
      }
    },
  );

  test(
    'cancellation discards a reply and prevents the next tool round',
    () async {
      final cancellation = AiCancellation();
      var calls = 0;
      final provider = ResponsesAgentProvider(
        client: MockClient((_) async {
          calls++;
          cancellation.cancel();
          return reply([call('staged_count')]);
        }),
      );
      await expectLater(
        provider.organize(request(cancellation: cancellation)),
        throwsA(isA<FormatException>()),
      );
      expect(calls, 1);
    },
  );

  test('missing marked tokens cannot become reviewable drafts', () async {
    final provider = ResponsesAgentProvider(
      client: MockClient(
        (_) async => reply([
          {
            'type': 'message',
            'content': [
              {
                'type': 'output_text',
                'text': jsonEncode({
                  'cards': [
                    {
                      'title': '资料',
                      'content': '遗漏的资料',
                      'kind': 'note',
                      'inference': false,
                    },
                  ],
                }),
              },
            ],
          },
        ]),
      ),
    );
    await expectLater(
      DraftAgentService(provider).propose(
        text: 'fictional-secret',
        marks: const [
          SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.secret),
        ],
        endpoint: request().endpoint,
        model: 'fictional-model',
        apiKey: 'fictional-test-key',
      ),
      throwsA(isA<FormatException>()),
    );
  });
}
