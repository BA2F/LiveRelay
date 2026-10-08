import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_conversation.dart';
import 'package:live_relay/application/workbench/window_speech_bridge.dart';
import 'package:live_relay/core/ports/speech_provider.dart';
import 'package:live_relay/core/ports/remote_speech_provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';
import 'remote_speech_test.dart' show wave;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final remote in [false, true]) {
    test(
      'speech scope is single use, keeps credentials in owner, separates storage and cancels late results (remote=$remote)',
      () async {
        FlutterSecureStorage.setMockInitialValues({});
        final root = await Directory.systemTemp.createTemp(
          'liverelay-window-speech-',
        );
        final provider = FixtureWindowSpeech();
        final service = createSpeechService(
          provider,
          supported: true,
          remoteProvider: provider,
        );
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
          service,
        );
        final q = AgentConversation(c);
        var active = true;
        final bridge = WindowSpeechBridge(c, q, active: () => active);
        Future<dynamic> invoke(String method, [Map args = const {}]) =>
            bridge.invoke(MethodCall(method, args));
        try {
          await c.initialize();
          await c.setupVault(
            password: 'fixture-speech-password',
            usesChinesePassphrase: false,
          );
          await service.configureRemote(
            name: 'fixture speech',
            endpoint: 'https://asr.invalid/upload?private-routing=fixture',
            model: 'fixture model',
            apiKey: 'fixture-private-key',
          );
          await service.chooseRemote(remote);
          expect(
            jsonEncode(windowSpeech(c)),
            isNot(contains('fixture-private-key')),
          );
          expect(
            jsonEncode(windowSpeech(c)),
            isNot(contains('private-routing')),
          );
          await expectLater(
            invoke('prepareSpeech', {
              'wav': Uint8List.fromList([1, 2]),
            }),
            throwsFormatException,
          );
          final input = wave();
          var prepared = await invoke('prepareSpeech', {'wav': input}) as Map;
          expect(prepared['host'], 'asr.invalid');
          await invoke('discardSpeech', {'ticket': prepared['ticket']});
          await expectLater(
            invoke('recognizeSpeech', {
              'ticket': prepared['ticket'],
              'saveOriginal': false,
            }),
            throwsFormatException,
          );
          expect(provider.calls, 0);
          prepared = await invoke('prepareSpeech', {'wav': input}) as Map;
          await service.chooseRemote(remote);
          await expectLater(
            invoke('recognizeSpeech', {
              'ticket': prepared['ticket'],
              'saveOriginal': false,
            }),
            throwsFormatException,
          );
          prepared = await invoke('prepareSpeech', {'wav': input}) as Map;
          var result = await invoke('recognizeSpeech', {
            'ticket': prepared['ticket'],
            'saveOriginal': false,
          }) as Map;
          expect(result['text'], '虚构转写');
          expect(c.blobs, isEmpty);
          expect(c.cards, isEmpty);
          expect(input, wave());
          expect(provider.last!.every((v) => v == 0), true);
          await expectLater(
            invoke('recognizeSpeech', {
              'ticket': prepared['ticket'],
              'saveOriginal': false,
            }),
            throwsFormatException,
          );
          await expectLater(
            invoke('saveSpeechDraft', {'text': 'edited', 'blobId': 'foreign'}),
            throwsFormatException,
          );
          await invoke('speechBackfill', {'text': '本人核对转写'});
          expect(q.draft, '本人核对转写');
          expect(ai.requests, isEmpty);
          prepared = await invoke('prepareSpeech', {'wav': input}) as Map;
          result = await invoke('recognizeSpeech', {
            'ticket': prepared['ticket'],
            'saveOriginal': true,
          }) as Map;
          expect(c.blobs, hasLength(1));
          expect(await c.readOriginal(c.blobs.single.id), wave());
          final saving = c.records.vault.changes.firstWhere(
            (_) => c.records.vault.isWriting,
          );
          q.updateDraft('待保存的助手草稿');
          final autosave = q.flush();
          await saving;
          expect(c.isBusy, true);
          await invoke('saveSpeechDraft', {
            'text': '本人校对文字',
            'blobId': result['blobId'],
          });
          await autosave;
          final draft = c.cards.singleWhere((card) => card.content == '本人校对文字');
          expect(
            (await c.cardSources(draft.id)).first.blobId,
            result['blobId'],
          );
          await q.flush();
          await c.lock();
          await c.unlockWithPassword('fixture-speech-password');
          await q.load();
          expect(q.draft, '待保存的助手草稿');
          expect(c.cards.any((card) => card.content == '本人校对文字'), true);
          provider.delay = true;
          prepared = await invoke('prepareSpeech', {'wav': input}) as Map;
          final request = invoke('recognizeSpeech', {
            'ticket': prepared['ticket'],
            'saveOriginal': true,
          });
          final rejected = expectLater(request, throwsFormatException);
          await provider.started.future;
          active = false;
          var cleaned = false;
          final cleanup = bridge.clear().then((_) => cleaned = true);
          await Future<void>.delayed(Duration.zero);
          expect(cleaned, false);
          provider.release.complete();
          await rejected;
          await cleanup;
          expect(provider.last!.every((v) => v == 0), true);
          expect(c.blobs, hasLength(1));
          await expectLater(
            invoke('speechBackfill', {'text': 'late'}),
            throwsFormatException,
          );
        } finally {
          if (!provider.release.isCompleted) provider.release.complete();
          await bridge.clear();
          q.dispose();
          await c.lock();
          c.dispose();
          await root.delete(recursive: true);
        }
      },
    );
  }
}

class FixtureWindowSpeech implements SpeechProvider, RemoteSpeechProvider {
  int calls = 0;
  bool delay = false;
  Uint8List? last;
  final started = Completer<void>(), release = Completer<void>();
  @override
  Future<bool> isModelInstalled() async => true;
  @override
  Future<void> downloadModel(SpeechDownloadProgress progress) async {}
  @override
  Future<void> installArchive(String path) async {}
  @override
  Future<void> removeModel() async {}
  @override
  Future<void> cancelDownload() async {}
  @override
  Future<String> transcribe(dynamic input) async {
    calls++;
    last = input is RemoteSpeechRequest ? input.wav : input as Uint8List;
    if (delay) {
      started.complete();
      await release.future;
    }
    return '虚构转写';
  }
}
