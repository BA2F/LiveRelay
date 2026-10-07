import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/infrastructure/ai/http_conversation_provider.dart';

/// Opt-in real upstream verification. Only the fixed public color fixture is
/// read; credentials arrive on stdin and never enter files, args or artifacts.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    throw ArgumentError('public evidence directory required');
  }
  stdout.writeln('Ready for stdin credential; terminal echo must be disabled.');
  var key = stdin.readLineSync()?.trim() ?? '';
  if (key.isEmpty) throw StateError('No credential supplied');
  final client = http.Client();
  final provider = HttpConversationProvider(client: client);
  final root = await Directory.systemTemp.createTemp(
    'liverelay-public-vision-',
  );
  final image = ConversationAttachment.read(
    'public-colors.png',
    await File('test/fixtures/vision-stripes.png').readAsBytes(),
  );
  ConversationAttachment? video;
  final results = <Map<String, Object?>>[];
  try {
    final clip = File('${root.path}/public-colors.mp4');
    final generated = await Process.run('ffmpeg', [
      '-nostdin',
      '-v',
      'error',
      '-loop',
      '1',
      '-i',
      'test/fixtures/vision-stripes.png',
      '-t',
      '2',
      '-r',
      '10',
      '-c:v',
      'mpeg4',
      '-pix_fmt',
      'yuv420p',
      clip.path,
    ]);
    if (generated.exitCode != 0) {
      throw StateError('Public clip generation failed');
    }
    video = ConversationAttachment.read(
      'public-colors.mp4',
      await clip.readAsBytes(),
    );
    for (final ms in [100, 700, 1300, 1900]) {
      final sampled = await Process.run('ffmpeg', [
        '-nostdin',
        '-v',
        'error',
        '-ss',
        '${ms / 1000}',
        '-i',
        clip.path,
        '-frames:v',
        '1',
        '-vf',
        'scale=480:-1',
        '-f',
        'image2pipe',
        '-vcodec',
        'mjpeg',
        'pipe:1',
      ], stdoutEncoding: null);
      if (sampled.exitCode != 0) {
        throw StateError('Public frame sampling failed');
      }
      video.frames.add((
        milliseconds: ms,
        bytes: Uint8List.fromList(sampled.stdout as List<int>),
      ));
    }
    for (final protocol in AiProtocol.values) {
      for (final attachment in [image, video]) {
        final prompt =
            'Inspect the supplied image regions. In reply give only '
            'the three large color regions in LEFT TO RIGHT order, using English '
            'color names. For sampled video frames report the same order if '
            'the frames agree. Return cards=[] and do not propose saving.';
        final parts = <Map<String, Object?>>[
          {
            'type': protocol == AiProtocol.responses ? 'input_text' : 'text',
            'text': prompt,
          },
          ...attachment.wireParts(protocol, images: true, files: false),
        ];
        final request = AiProviderRequest(
          endpoint: Uri.parse('https://api.deepseek.com'),
          apiKey: key,
          model: 'deepseek-flash',
          protocol: protocol,
          redactedText: prompt,
          inputContent: parts,
        );
        final answer = await provider.converse(request, []);
        checkColors(answer.content);
        var historyReplayed = false;
        if (attachment.kind == ConversationAttachmentKind.image) {
          final followup = await provider.converse(
            AiProviderRequest(
              endpoint: request.endpoint,
              apiKey: key,
              model: request.model,
              protocol: protocol,
              redactedText:
                  'Repeat the previously observed left-to-right colors '
                  'in English in reply, with cards=[].',
            ),
            [
              {'role': 'user', 'content': parts},
              ...answer.output,
            ],
          );
          checkColors(followup.content);
          historyReplayed = true;
        }
        results.add({
          'protocol': protocol.name,
          'attachment': attachment.kind.name,
          'colorsVerified': true,
          'imageHistoryReplayed': historyReplayed,
          'imageCount': attachment.kind == ConversationAttachmentKind.video
              ? video.frames.length
              : 1,
          'videoOriginalUploaded': false,
        });
        stdout.writeln('${protocol.name}/${attachment.kind.name}: passed');
      }
    }
    final evidence = await Directory(args.single).create(recursive: true);
    await File(
      '${evidence.path}/deepseek-vision-verification.json',
    ).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({'date': '2026-10-07', 'realUpstream': true, 'model': 'deepseek-flash', 'publicSyntheticFixtureOnly': true, 'productionHttpAdapter': true, 'productionAttachmentWire': true, 'nativeUiSession': false, 'privateVaultAccess': false, 'cardConfirmation': false, 'credentialPersisted': false, 'rawAudioUploaded': false, 'pdfUploaded': false, 'results': results})}\n',
    );
  } catch (error) {
    stderr.writeln(
      'Verification failed (${error.runtimeType}); no response body or credential printed.',
    );
    exitCode = 1;
  } finally {
    key = '';
    client.close();
    image.wipe();
    video?.wipe();
    await root.delete(recursive: true);
  }
}

void checkColors(String content) {
  final data = jsonDecode(content) as Map;
  final reply = (data['reply'] as String).toLowerCase();
  final positions = [
    for (final color in ['red', 'green', 'blue']) reply.indexOf(color),
  ];
  if (positions.any((p) => p < 0) ||
      positions[0] >= positions[1] ||
      positions[1] >= positions[2] ||
      (data['cards'] as List).isNotEmpty) {
    throw StateError('Public fixture color assertion failed');
  }
}
