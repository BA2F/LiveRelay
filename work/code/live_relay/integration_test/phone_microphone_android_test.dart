import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/speech/pcm_wave.dart';
import 'package:live_relay/presentation/pages/speech_input_page.dart';

import '../test/support/verification_fakes.dart';

/// Requires the human to tap Record and read ONLY the agreed fictional phrase.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'physical microphone through production speech page',
    (tester) async {
      final support = await getApplicationSupportDirectory();
      final inputs = Directory('${support.path}/verification-speech');
      final root = await support.createTemp('fictional-microphone-');
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      try {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: Center(child: Text('准备录音联调：等待模型；仅朗读已约定的虚构句子')),
            ),
          ),
        );
        await tester.pump();
        debugPrint('SPEECH_INPUT_READY');
        final archive = File('${inputs.path}/model.tar.bz2');
        for (var i = 0; i < 120 && !await archive.exists(); i++) {
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        expect(await archive.exists(), isTrue);
        await c.initialize();
        final recovery = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-microphone-password',
          recoveryText: recovery,
          recoveryConfirmation: recovery,
        );
        await c.speech!.install(archive.path);
        await tester.pumpWidget(
          ChangeNotifierProvider<AppController>.value(
            value: c,
            child: const MaterialApp(home: SpeechInputPage()),
          ),
        );
        await tester.pump();
        debugPrint(
          'PHONE_MIC_READY: human must tap 开始录音 and read fictional phrase',
        );
        for (var i = 0; i < 240 && find.text('停止并识别').evaluate().isEmpty; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await tester.pump();
        }
        expect(find.text('停止并识别'), findsOneWidget);
        debugPrint('PHONE_MIC_STARTED: automatically stop after 12 seconds');
        await Future<void>.delayed(const Duration(seconds: 12));
        await tester.tap(find.text('停止并识别'));
        await tester.pump();
        for (var i = 0; i < 240; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          await tester.pump();
          final field = tester.widget<TextField>(find.byType(TextField));
          if (!c.speech!.busy && field.controller!.text.isNotEmpty) break;
        }
        final text = tester
            .widget<TextField>(find.byType(TextField))
            .controller!
            .text;
        expect(text, isNotEmpty);
        expect(text, anyOf(contains('测试'), contains('资料'), contains('明天')));
        final blobId = c.blobs.single.id;
        final wav = await c.readOriginal(blobId);
        final seconds = PcmWave.decode(wav).length / 16000;
        wav.fillRange(0, wav.length, 0);
        expect(seconds, greaterThan(1));
        expect(seconds, lessThanOrEqualTo(60));
        final save = find.text('已核对，保存文字草稿');
        await tester.ensureVisible(save);
        await tester.tap(save);
        for (var i = 0; i < 40; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          await tester.pump();
          if (c.cards.any((card) => card.content == text)) break;
        }
        await c.lock();
        await c.unlockDaily(password: 'fictional-microphone-password');
        final card = c.cards.firstWhere((v) => v.content == text);
        expect((await c.cardSources(card.id)).single.blobId, blobId);
        debugPrint(
          'PHONE_MIC_RESULT: audioSeconds=$seconds; fictionalText=$text; sourceLinkedAfterReopen=true',
        );
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump();
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
        if (await inputs.exists()) await inputs.delete(recursive: true);
      }
    },
    skip: !Platform.isAndroid,
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
