import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';
import 'package:live_relay/infrastructure/ai/http_conversation_provider.dart';

void main() {
  test('large encrypted conversation state chunks roundtrip and stale parts are removed', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      final state = jsonEncode({
        'version': 1,
        'fixture': 'x' * 1100000 + '中文🙂',
      });
      await r.writeChunkedLocalValue('agent.conversation.v1', state);
      expect(await r.readChunkedLocalValue('agent.conversation.v1'), state);
      expect(
        await r.readLocalValue('agent.conversation.v1'),
        contains('chunked'),
      );
      await r.writeChunkedLocalValue('agent.conversation.v1', '{"version":1}');
      expect(
        await r.readChunkedLocalValue('agent.conversation.v1'),
        '{' '"version":1}',
      );
      expect(await r.readLocalValue('agent.conversation.v1.part0'), isNull);
    } finally {
      await r.close();
    }
  });

  test('reviewed saved originals are linked in one transaction without expanding release', () async {
    final r = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      await r.registerBlob(
        VaultBlob(
          id: 'fixture-original',
          originalName: 'fixture.txt',
          mediaKind: BlobMediaKind.document,
          mimeType: 'text/plain',
          relativePath: 'blobs/fixture',
          byteLength: 1,
          sha256: 'fixture',
          createdAt: DateTime.utc(2026),
        ),
      );
      final cards = await r.saveReviewedAgentSuggestions(
        'fixture-source-review',
        'explicit scope',
        [const CardDraft(title: 'summary', content: 'reviewed')],
        providerLabel: 'fixture',
        originalIds: ['fixture-original'],
      );
      expect(
        (await r.currentCardSources(cards.single.id))
            .any((s) => s.blobId == 'fixture-original'),
        true,
      );
      expect(cards.single.status, CardStatus.confirmed);
      expect(
        (await r.getReleasePolicy(
          'card',
          cards.single.id,
        )).visibleAt(LifeState.deceased),
        VisibilityLevel.hidden,
      );
      final count = (await r.listCards()).length;
      await expectLater(
        r.saveReviewedAgentSuggestions(
          'invalid-source-review',
          'scope',
          [const CardDraft(title: 'rollback', content: 'reviewed')],
          providerLabel: 'fixture',
          originalIds: ['missing'],
        ),
        throwsFormatException,
      );
      expect((await r.listCards()).length, count);
      expect(
        await r.readLocalValue('agent.review.invalid-source-review'),
        isNull,
      );
    } finally {
      await r.close();
    }
  });

  test('attachments use verified image/PDF/text protocol parts and require declared capabilities', () async {
    final image = ConversationAttachment.read(
      'fixture.png',
      Uint8List.fromList([137, 80, 78, 71, 13, 10, 26, 10, 0]),
    );
    final pdf = ConversationAttachment.read(
      'fixture.pdf',
      Uint8List.fromList(utf8.encode('%PDF-fixture')),
    );
    final text = ConversationAttachment.read(
      'fixture.md',
      Uint8List.fromList(utf8.encode('explicit fixture text')),
    );
    expect(
      () => image.wire(AiProtocol.responses, images: false, files: true),
      throwsFormatException,
    );
    expect(
      () => pdf.wire(AiProtocol.chatCompletions, images: true, files: true),
      throwsFormatException,
    );
    expect(
      () => ConversationAttachment.read(
        'fixture.wav',
        Uint8List.fromList([0, 1, 2]),
      ).wire(AiProtocol.responses, images: true, files: true),
      throwsFormatException,
    );
    final parts = [
      image.wire(AiProtocol.responses, images: true, files: true),
      pdf.wire(AiProtocol.responses, images: true, files: true),
      text.wire(AiProtocol.responses, images: true, files: true),
    ];
    final provider = HttpConversationProvider(
      client: MockClient((request) async {
        final body = jsonDecode(request.body);
        expect(body['input'].last['content'], parts);
        expect(
          base64Decode(
            (body['input'].last['content'][0]['image_url'] as String)
                .split(',')
                .last,
          ),
          image.bytes,
        );
        expect(body['input'].last['content'][1]['filename'], 'fixture.pdf');
        expect(body['store'], false);
        return http.Response(
          '{"output":[{"type":"message","content":[{"type":"output_text","text":"{\\"reply\\":\\"ok\\",\\"cards\\":[]}"}]}]}',
          200,
        );
      }),
    );
    await provider.converse(
      AiProviderRequest(
        endpoint: Uri.parse('https://fixture.invalid/responses'),
        apiKey: 'fixture',
        model: 'fixture',
        protocol: AiProtocol.responses,
        redactedText: 'scope',
        inputContent: parts,
      ),
      [],
    );
    expect(
      image.wire(
        AiProtocol.chatCompletions,
        images: true,
        files: false,
      )['type'],
      'image_url',
    );
    expect(ConversationAttachment.fromJson(image.toJson()).bytes, image.bytes);
    image.wipe();
    expect(image.bytes.every((b) => b == 0), true);
  });
  test(
    'binary limits, invalid text and mismatched persisted kind are rejected',
    () {
      expect(
        () => ConversationAttachment.read(
          'huge.pdf',
          Uint8List(ConversationAttachment.maxBytes + 1),
        ),
        throwsFormatException,
      );
      expect(
        () => ConversationAttachment.read(
          'invalid.txt',
          Uint8List.fromList([255]),
        ),
        throwsFormatException,
      );
      final raw = ConversationAttachment.read(
        'fixture.txt',
        Uint8List.fromList([65]),
      ).toJson();
      raw['kind'] = 'image';
      expect(() => ConversationAttachment.fromJson(raw), throwsFormatException);
    },
  );
}
