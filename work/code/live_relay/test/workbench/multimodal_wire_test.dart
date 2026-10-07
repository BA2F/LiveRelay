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
  test('M4A keeps its immutable original while normalized audio or reviewed text define the exact wire scope', () {
    final original = Uint8List.fromList([0, 0, 0, 12, 102, 116, 121, 112, 77, 52, 65, 32]);
    final media = ConversationAttachment.read('fixture.m4a', original);
    media.normalizedAudio = wave();
    final raw = media.toJson();
    final restored = ConversationAttachment.fromJson(raw);
    final audio = restored.wireParts(AiProtocol.chatCompletions, images: false, files: false, audio: true).single;
    expect((audio['input_audio'] as Map)['format'], 'wav');
    expect(base64Decode((audio['input_audio'] as Map)['data']), wave());
    expect(restored.bytes, original);
    restored.transcript = '本人已核对文字';
    for (final protocol in AiProtocol.values) {
      final text = restored.wireParts(protocol, images: false, files: false).single;
      expect(jsonEncode(text), contains('本人已核对文字'));
      expect(jsonEncode(text), isNot(contains('input_audio')));
      expect(jsonEncode(text), isNot(contains('base64')));
    }
    final derived = restored.normalizedAudio!;
    final rawBytes = restored.bytes;
    restored.wipe();
    expect(derived.every((v) => v == 0), true);
    expect(rawBytes.every((v) => v == 0), true);
    expect(original.take(4), [0, 0, 0, 12]);
    expect(() => ConversationAttachment.fromJson({...raw, 'normalizedAudio': base64Encode(Uint8List(4))}), throwsFormatException);
    media.wipe();
  });
  test('video explicitly sends complete chosen audio or reviewed transcript with checked frames', () {
    final video = ConversationAttachment.read('fixture.mp4', Uint8List.fromList([0, 0, 0, 12, 102, 116, 121, 112, 105, 115, 111, 109]));
    video.frames.add((milliseconds: 100, bytes: Uint8List.fromList([255, 216, 255, 217])));
    video.normalizedAudio = wave();
    var parts = video.wireParts(AiProtocol.chatCompletions, images: true, files: false, audio: true);
    expect(parts.where((p) => p['type'] == 'input_audio'), hasLength(1));
    expect(jsonEncode(parts), contains('另发送完整转换音轨'));
    expect(() => video.wireParts(AiProtocol.responses, images: true, files: false), throwsFormatException);
    video.transcript = '本人核对视频音轨';
    parts = video.wireParts(AiProtocol.responses, images: true, files: false);
    expect(parts.where((p) => p['type'] == 'input_audio'), isEmpty);
    expect(jsonEncode(parts), contains('本人核对视频音轨'));
    final restored = ConversationAttachment.fromJson(video.toJson());
    expect(restored.transcript, video.transcript);
    expect(restored.normalizedAudio, wave());
    video.wipe(); restored.wipe();
  });
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
    expect(jsonEncode(parts), contains('不发送视频原件'));
    expect(jsonEncode(parts), contains('不发送音轨'));
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
