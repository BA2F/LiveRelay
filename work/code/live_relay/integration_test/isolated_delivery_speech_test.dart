import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:live_relay/application/local_handoff_service.dart';
import 'package:live_relay/application/recipient_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/identity/local_identity.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/speech/local_sense_voice_provider.dart';
import 'package:live_relay/infrastructure/speech/pcm_wave.dart';

import '../test/support/verification_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native independent identities preserve explicit scope after reopen',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('native-delivery-');
      final ownerRoot = Directory('${root.path}/owner');
      final recipientRoot = Directory('${root.path}/recipient');
      var c = createAppController(
        ownerRoot,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      var receiver = RecipientService(() async => recipientRoot);
      final wrong = RecipientService(
        () async => Directory('${root.path}/wrong'),
      );
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: Center(child: Text('双独立身份限定交接：虚构资料'))),
        ),
      );
      try {
        await c.initialize();
        final recovery = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-delivery-password',
          recoveryText: recovery,
          recoveryConfirmation: recovery,
        );
        await c.saveOwnerProfile('虚构所有者', 'fixture', 'owner-private-note');
        await c.createCard(
          const CardDraft(title: '摘要标题', content: 'unselected-private-body'),
        );
        final cardId = c.cards.single.id;
        await c.updateCard(
          cardId,
          const CardDraft(title: '摘要标题', content: 'current-private-body'),
        );
        await c.saveCredential(
          const CredentialDraft(
            title: '虚构账号',
            username: 'fixture',
            secret: 'old-private-secret',
          ),
        );
        final credentialId = c.credentials.single.id;
        await c.saveCredential(
          const CredentialDraft(
            title: '虚构账号',
            username: 'fixture',
            secret: 'current-private-secret',
          ),
          id: credentialId,
        );
        final original = await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('explicit-original')),
          originalName: 'fictional.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        final blobId = c.blobs.single.id;
        await receiver.initialize();
        await receiver.create('虚构接收者', 'fictional-recipient-password');
        final fp = await receiver.identity!.fingerprint();
        final owner = c.handoff!;
        final ownerFp = await LocalIdentity.fingerprintOf(
          await owner.publicIdentity(),
        );
        final challenge = jsonDecode(
          utf8.decode(
            await owner.createChallenge(
              await receiver.identity!.publicData(),
              fp,
            ),
          ),
        ) as Map<String, Object?>;
        final proof = jsonDecode(
          utf8.decode(await receiver.answerChallenge(challenge, ownerFp)),
        ) as Map<String, Object?>;
        await owner.acceptProof(proof);
        final summary = await owner.exportScope(fp, [
          ScopedRecord('card', cardId, VisibilityLevel.existence),
          ScopedRecord('credential', credentialId, VisibilityLevel.summary),
        ]);
        await receiver.receive(summary, ownerFp);
        final payload = jsonEncode(receiver.snapshot);
        for (final excluded in [
          'unselected-private-body',
          'current-private-body',
          'old-private-secret',
          'current-private-secret',
          'explicit-original',
          'owner-private-note',
        ]) {
          expect(payload, isNot(contains(excluded)));
        }
        expect((receiver.snapshot!['originals'] as Map), isEmpty);
        await expectLater(receiver.receive(summary, ownerFp), throwsStateError);
        await wrong.initialize();
        await wrong.create('错误接收者', 'fictional-wrong-password');
        await expectLater(
          wrong.receive(summary, ownerFp),
          throwsFormatException,
        );
        final full = await owner.exportScope(fp, [
          ScopedRecord('card', cardId, VisibilityLevel.full, history: true),
          ScopedRecord(
            'credential',
            credentialId,
            VisibilityLevel.secret,
            history: true,
          ),
          ScopedRecord(
            'card',
            original.id,
            VisibilityLevel.original,
            originalIds: [blobId],
          ),
        ]);
        await receiver.receive(full, ownerFp);
        final approved = jsonEncode(receiver.snapshot);
        for (final allowed in [
          'current-private-body',
          'unselected-private-body',
          'current-private-secret',
          'old-private-secret',
        ]) {
          expect(approved, contains(allowed));
        }
        expect(
          utf8.decode(
            base64Url.decode(
              base64Url.normalize(
                ((receiver.snapshot!['originals'] as Map)[blobId]
                        as Map)['bytes']
                    as String,
              ),
            ),
          ),
          'explicit-original',
        );
        await c.lock();
        c.dispose();
        c = createAppController(
          ownerRoot,
          NoBiometrics(),
          TestOcr(),
          RecordingAi(),
          TestAiSettings(),
        );
        await c.initialize();
        await c.unlockDaily(password: 'fictional-delivery-password');
        expect((await c.handoff!.recipients()).containsKey(fp), isTrue);
        expect(
          await LocalIdentity.fingerprintOf(await c.handoff!.publicIdentity()),
          ownerFp,
        );
        receiver.dispose();
        receiver = RecipientService(() async => recipientRoot);
        await receiver.initialize();
        await receiver.unlock('fictional-recipient-password');
        await expectLater(receiver.receive(summary, ownerFp), throwsStateError);
        await expectLater(receiver.receive(full, ownerFp), throwsStateError);
        final saved = (await receiver.savedPackages()).singleWhere(
          (f) =>
              jsonDecode(utf8.decode(f.readAsBytesSync()))['packageId'] ==
              jsonDecode(utf8.decode(full))['packageId'],
        );
        await receiver.receive(await saved.readAsBytes(), ownerFp, saved: true);
        expect(jsonEncode(receiver.snapshot), approved);
        expect(
          await File('${recipientRoot.path}/vault.sqlite').exists(),
          isFalse,
        );
        debugPrint(
          'NATIVE_DELIVERY: scope, originals, wrong target, replay and independent reopen passed',
        );
      } finally {
        receiver.dispose();
        wrong.dispose();
        await c.lock();
        c.dispose();
        await tester.pumpWidget(const SizedBox());
        await root.delete(recursive: true);
      }
    },
    skip: const bool.fromEnvironment('PUBLIC_SPEECH_ONLY'),
  );

  if (Platform.isAndroid) {
    testWidgets(
      'physical Android local SenseVoice recognizes public WAV and keeps draft source',
      (tester) async {
        final support = await getApplicationSupportDirectory();
        final inputs = Directory('${support.path}/verification-speech');
        final root = await support.createTemp('public-speech-');
        final provider = LocalSenseVoiceProvider(
          () async => Directory('${root.path}/model'),
        );
        final c = createAppController(
          root,
          NoBiometrics(),
          TestOcr(),
          RecordingAi(),
          TestAiSettings(),
        );
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(body: Center(child: Text('手机本地转写：仅公开 WAV，不访问麦克风'))),
          ),
        );
        final archive = File('${inputs.path}/model.tar.bz2'),
            wav = File('${inputs.path}/public.wav');
        debugPrint('SPEECH_INPUT_READY');
        try {
          for (
            var i = 0;
            i < 120 && (!await archive.exists() || !await wav.exists());
            i++
          ) {
            await Future<void>.delayed(const Duration(seconds: 1));
          }
          expect(await archive.exists(), isTrue);
          expect(await wav.exists(), isTrue);
          final install = Stopwatch()..start();
          await provider.installArchive(archive.path);
          install.stop();
          final bytes = await wav.readAsBytes(),
              seconds = PcmWave.decode(await wav.readAsBytes()).length / 16000;
          final timer = Stopwatch()..start();
          debugPrint('SPEECH_TRANSCRIBE_READY');
          final text = await provider.transcribe(bytes);
          timer.stop();
          expect(text, contains('时间'));
          await c.initialize();
          final r = await c.generateRecovery();
          await c.setupModernVault(
            password: 'fictional-speech-password',
            recoveryText: r,
            recoveryConfirmation: r,
          );
          await c.importOriginal(
            bytes: Uint8List.fromList(bytes),
            originalName: 'public.wav',
            mimeType: 'audio/wav',
            mediaKind: BlobMediaKind.audio,
          );
          final blobId = c.blobs.single.id;
          await c.saveSpeechDraft(text, blobId: blobId);
          await c.lock();
          await c.unlockDaily(password: 'fictional-speech-password');
          final card = c.cards.firstWhere((v) => v.content == text);
          expect((await c.cardSources(card.id)).single.blobId, blobId);
          expect(await c.readOriginal(blobId), bytes);
          await provider.removeModel();
          expect(await provider.isModelInstalled(), isFalse);
          debugPrint(
            'PHONE_SPEECH_RESULT: ${jsonEncode({'installMs': install.elapsedMilliseconds, 'transcribeMs': timer.elapsedMilliseconds, 'audioSeconds': seconds, 'text': text, 'sourceLinkedAfterReopen': true})}',
          );
        } finally {
          await c.lock();
          c.dispose();
          await tester.pumpWidget(const SizedBox());
          await root.delete(recursive: true);
          if (await inputs.exists()) await inputs.delete(recursive: true);
        }
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  }
}
