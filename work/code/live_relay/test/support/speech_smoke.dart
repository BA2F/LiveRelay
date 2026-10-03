import 'dart:io';

import 'package:live_relay/infrastructure/speech/local_sense_voice_provider.dart';

/// Public upstream audio/model only, no user vault or microphone access.
Future<void> main(List<String> args) async {
  if (args.length != 3) {
    throw ArgumentError('archive, isolated model directory, public WAV');
  }
  final provider = LocalSenseVoiceProvider(
    () => Future.value(Directory(args[1])),
  );
  if (!await provider.isModelInstalled()) {
    await provider.installArchive(args[0]);
  }
  final text = await provider.transcribe(await File(args[2]).readAsBytes());
  if (text.trim().isEmpty || !text.contains('时间')) {
    throw StateError('Public Chinese sample was not recognized');
  }
  stdout.writeln('Local SenseVoice public sample recognized: $text');
}
