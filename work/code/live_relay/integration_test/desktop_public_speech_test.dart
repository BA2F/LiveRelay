import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/speech/local_sense_voice_provider.dart';
import 'package:live_relay/presentation/pages/speech_input_page.dart';

import '../test/support/verification_fakes.dart';

/// Opt-in public upstream model/sample; no microphone or personal vault access.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStorage.setMockInitialValues({});
  final modelRoot = Platform.environment['LIVERELAY_PUBLIC_SPEECH_MODEL_ROOT'];
  final wavPath = Platform.environment['LIVERELAY_PUBLIC_SPEECH_WAV'];
  testWidgets(
    'native shared speech page recognizes public audio with real local model and encrypted optional original',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-public-speech-',
      );
      final local = LocalSenseVoiceProvider(() async => Directory(modelRoot!));
      final speech = createSpeechService(local);
      final ai = RecordingConversationAi();
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        ai,
        TestAiSettings(),
        null,
        null,
        null,
        speech,
      );
      final conversation = AgentConversation(c);
      final key = GlobalKey<SpeechInputPageState>();
      final boundary = GlobalKey();
      final file = File(wavPath!);
      try {
        await c.initialize();
        await c.setupVault(
          password: 'public-local-speech-password',
          usesChinesePassphrase: false,
        );
        await speech.refresh();
        expect(speech.installed, true);
        expect(speech.usingRemote, false);
        conversation.updateDraft('已有测试输入');
        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: c,
            child: MaterialApp(
              home: RepaintBoundary(
                key: boundary,
                child: SpeechInputPage(
                  key: key,
                  onTranscript: (text) {
                    conversation.updateDraft('${conversation.draft}\n$text');
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(key.currentState!.savesOriginal, false);
        await key.currentState!.importAudioFile(file);
        await tester.pumpAndSettle(
          const Duration(milliseconds: 100),
          EnginePhase.sendSemanticsUpdate,
          const Duration(seconds: 10),
        );
        expect(speech.busy, false);
        final transcript = key.currentState!.transcript;
        expect(transcript, contains('时间'));
        expect(c.blobs, isEmpty);
        key.currentState!.backfillTranscript();
        expect(conversation.draft, startsWith('已有测试输入\n'));
        expect(conversation.draft, contains(transcript));
        expect(ai.requests, isEmpty);
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          await Directory(evidence).create(recursive: true);
          final render =
              boundary.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          await File('$evidence/native-public-local-speech.png')
              .writeAsBytes(data!.buffer.asUint8List());
        }
        key.currentState!.chooseSaveOriginal(true);
        await key.currentState!.importAudioFile(file);
        expect(c.blobs, hasLength(1));
        final original = await c.readOriginal(c.blobs.single.id);
        final publicWav = await file.readAsBytes();
        expect(original, publicWav);
        original.fillRange(0, original.length, 0);
        final existingCards = c.cards.map((card) => card.id).toSet();
        await key.currentState!.saveTranscriptDraft();
        final draft = c.cards
            .where((card) => !existingCards.contains(card.id))
            .single;
        expect(draft.status, CardStatus.draft);
        expect(draft.content, contains('时间'));
        final cardId = draft.id;
        expect(
          (await c.cardsForBlob(c.blobs.single.id)).map((card) => card.id),
          contains(cardId),
        );
        await conversation.flush();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 300));
        await c.lock();
        await c.unlockWithPassword('public-local-speech-password');
        expect(
          c.cards.singleWhere((card) => card.id == cardId).status,
          CardStatus.draft,
        );
        await conversation.load();
        expect(conversation.draft, contains(transcript));
        expect(conversation.draft, startsWith('已有测试输入\n'));
        expect(c.blobs, hasLength(1));
        final reopened = await c.readOriginal(c.blobs.single.id);
        expect(reopened, publicWav);
        reopened.fillRange(0, reopened.length, 0);
        if (evidence != null) {
          await File(
            '$evidence/public-local-speech-verification.json',
          ).writeAsString(
            '${const JsonEncoder.withIndent('  ').convert({'date': '2026-10-07', 'realNativeSharedPage': true, 'realLocalSenseVoice': true, 'publicUpstreamSampleOnly': true, 'publicSampleSha256': sha256.convert(publicWav).toString(), 'sampleBytes': publicWav.length, 'recognizedTimeWord': true, 'defaultNoOriginal': true, 'optionalOriginalMatches': true, 'editableBackfillPreservesDraft': true, 'automaticAiRequests': 0, 'encryptedReopen': true, 'microphoneHardwareTested': false, 'remoteAsrTested': false})}\n',
          );
        }
        publicWav.fillRange(0, publicWav.length, 0);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        conversation.dispose();
        if (c.isUnlocked) await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
    skip: modelRoot == null || wavPath == null,
  );
}
