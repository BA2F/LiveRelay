import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/http_conversation_provider.dart';

import 'remote_speech_test.dart' show wave;

void main() {
  test('audio is explicit Chat input_audio; videos send checked frames and time, never disguised binary', () {
    final audio = ConversationAttachment.read('fixture.wav', wave());
    expect(audio.kind, ConversationAttachmentKind.audio);
    expect(
      () => audio.wireParts(
        AiProtocol.chatCompletions,
        images: false,
        files: false,
      ),
      throwsFormatException,
    );
    final part = audio
        .wireParts(
          AiProtocol.chatCompletions,
          images: false,
          files: false,
          audio: true,
        )
        .single;
    expect(part['type'], 'input_audio');
    expect((part['input_audio'] as Map)['format'], 'wav');
    expect(
      base64Decode((part['input_audio'] as Map)['data']),
      orderedEquals(audio.bytes),
    );
    expect(
      () => audio.wireParts(
        AiProtocol.responses,
        images: false,
        files: false,
        audio: true,
      ),
      throwsFormatException,
    );
    final video = ConversationAttachment.read(
      'fixture.mp4',
      Uint8List.fromList([0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109]),
    );
    expect(video.kind, ConversationAttachmentKind.video);
    expect(
      () => video.wireParts(
        AiProtocol.chatCompletions,
        images: true,
        files: true,
      ),
      throwsFormatException,
    );
    video.frames.add((
      milliseconds: 100,
      bytes: Uint8List.fromList([255, 216, 255, 217]),
    ));
    final checked = ConversationAttachment.fromJson(video.toJson());
    final parts = checked.wireParts(
      AiProtocol.responses,
      images: true,
      files: false,
    );
    expect(parts.map((p) => p['type']), [
      'input_text',
      'input_text',
      'input_image',
    ]);
    expect(jsonEncode(parts), contains('不发送视频原件或音轨'));
    final frame = checked.frames.single.bytes;
    checked.wipe();
    expect(frame.every((v) => v == 0), true);
  });
  test('audio-capable Chat requests omit unsupported JSON-mode while historical audio still replays with store=false', () async {
    final audio = ConversationAttachment.read('fixture.wav', wave());
    final content = audio.wireParts(
      AiProtocol.chatCompletions,
      images: false,
      files: false,
      audio: true,
    );
    final provider = HttpConversationProvider(
      client: MockClient((r) async {
        final body = jsonDecode(r.body) as Map;
        expect(body['store'], false);
        expect(body.containsKey('response_format'), false);
        expect(body['modalities'], ['text']);
        expect(jsonEncode(body['messages']), contains('input_audio'));
        return http.Response(
          '{"choices":[{"message":{"content":"{\\"reply\\":\\"fixture\\",\\"cards\\":[]}"}}]}',
          200,
        );
      }),
    );
    final response = await provider.converse(
      AiProviderRequest(
        endpoint: Uri.parse('https://fixture.invalid/chat'),
        apiKey: 'fixture-only-key',
        model: 'audio-model',
        redactedText: 'follow-up',
      ),
      [
        {'role': 'user', 'content': content},
      ],
    );
    expect(response.content, contains('fixture'));
  });
}
