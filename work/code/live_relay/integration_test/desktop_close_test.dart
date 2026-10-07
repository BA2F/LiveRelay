import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:window_manager/window_manager.dart';
import 'package:live_relay/application/workbench/workbench_runtime.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/workbench/native_close_guard.dart';

import '../test/support/verification_fakes.dart';

const password = 'public-close-fixture-password';

Future<void> main(List<String> args) async {
  if (args.firstOrNull == '--close-fixture') {
    WidgetsFlutterBinding.ensureInitialized();
    await fixture(Directory(args[1]), args[2]);
    return;
  }
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real GTK main close cancels when blocked, saves before exit; committed data survives SIGKILL',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-main-close-',
      );
      final results = <Map<String, Object?>>[];
      Future<Map> waitStatus(Directory dir, String expected) async {
        final file = File('${dir.path}/status.json');
        for (var tick = 0; tick < 200; tick++) {
          try {
            final data = jsonDecode(await file.readAsString()) as Map;
            if (data['status'] == expected) return data;
          } on Object {
            /* file is being replaced */
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        throw StateError('Main close fixture did not reach $expected');
      }

      try {
        for (final mode in ['close', 'crash']) {
          final dir = await Directory('${root.path}/$mode').create();
          // Driver VM pause switches belong to the harness, not this child.
          final environment = Map<String, String>.of(Platform.environment)
            ..removeWhere(
              (key, _) =>
                  key.startsWith('FLUTTER_ENGINE_SWITCH_') ||
                  key == 'DART_VM_OPTIONS',
            );
          final process = await Process.start(
            Platform.resolvedExecutable,
            ['--close-fixture', dir.path, mode],
            environment: environment,
            includeParentEnvironment: false,
          );
          process.stdout.drain<void>();
          process.stderr.drain<void>();
          try {
            await waitStatus(dir, 'ready');
            if (mode == 'close') {
              await File('${dir.path}/command').writeAsString('blocked');
              await waitStatus(dir, 'cancel');
              // A cancelled native close keeps the real process alive.
              var exited = false;
              process.exitCode.then((_) => exited = true);
              await Future<void>.delayed(const Duration(milliseconds: 200));
              expect(exited, false);
              await File('${dir.path}/command').writeAsString('save');
              await waitStatus(dir, 'exit');
              expect(
                await process.exitCode.timeout(const Duration(seconds: 10)),
                0,
              );
            } else {
              expect(process.kill(ProcessSignal.sigkill), true);
              expect(
                await process.exitCode.timeout(const Duration(seconds: 10)),
                isNot(0),
              );
            }
            final c = createAppController(
              dir,
              NoBiometrics(),
              TestOcr(),
              RecordingConversationAi(),
              TestAiSettings(),
            );
            final runtime = WorkbenchRuntime(c);
            try {
              await c.initialize();
              await c.unlockWithPassword(password);
              expect(c.cards.single.title, 'saved-$mode');
              expect(c.cards.single.status, CardStatus.draft);
              await runtime.load();
              expect(runtime.conversation.draft, 'conversation-$mode');
              expect(runtime.layout.containing('changes'), isNotNull);
              results.add({
                'mode': mode,
                'nativeProcess': true,
                'encryptedReopen': true,
                'draftNotConfirmed': true,
                'committedOnly': mode == 'crash',
              });
            } finally {
              runtime.dispose();
              await c.lock();
              c.dispose();
            }
          } finally {
            process.kill(ProcessSignal.sigkill);
            await process.exitCode;
          }
        }
        final evidence = Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidence != null) {
          final backend = Platform.environment['GDK_BACKEND'] == 'wayland'
              ? 'wayland'
              : 'x11';
          await Directory(evidence).create(recursive: true);
          await File('$evidence/native-main-close-$backend-verification.json')
              .writeAsString(
                jsonEncode({
                  'backend': backend,
                  'fixtureOnly': true,
                  'realGtkCloseRequest': true,
                  'blockedCloseKeepsWindow': true,
                  'savedCloseExits': true,
                  'forcedExitDoesNotGuaranteeUnsavedData': true,
                  'results': results,
                }),
              );
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}

Future<void> fixture(Directory root, String mode) async {
  final c = createAppController(
    root,
    NoBiometrics(),
    TestOcr(),
    RecordingConversationAi(),
    TestAiSettings(),
  );
  await c.initialize();
  await c.setupVault(password: password, usesChinesePassphrase: false);
  await c.createCard(
    const CardDraft(
      title: 'before',
      content: 'public fixture',
      status: CardStatus.draft,
    ),
  );
  final runtime = WorkbenchRuntime(c);
  await runtime.load();
  c.isBusy = mode == 'close';
  runtime.edits.edit(
    runtime.edits.session(c.cards.single),
    title: 'saved-$mode',
  );
  runtime.conversation.updateDraft('conversation-$mode');
  runtime.layout.open('changes');
  if (mode == 'crash') await runtime.flush();
  Future<void> status(String value) =>
      File('${root.path}/status.json')
          .writeAsString(jsonEncode({'status': value}));
  c.desktopExitRequested = () async {
    final result = await runtime.requestExit();
    await status(result == AppExitResponse.cancel ? 'cancel' : 'exit');
    return result;
  };
  runApp(
    MaterialApp(
      home: NativeCloseGuard(
        controller: c,
        child: const Scaffold(body: Text('Public main close fixture')),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await status('ready');
  if (mode == 'close') {
    var last = '';
    var reading = false;
    Timer.periodic(const Duration(milliseconds: 100), (_) async {
      if (reading) return;
      reading = true;
      try {
        final file = File('${root.path}/command');
        if (!await file.exists()) return;
        final command = await file.readAsString();
        if (command == last) return;
        last = command;
        c.isBusy = command == 'blocked';
        await windowManager.close();
      } finally {
        reading = false;
      }
    });
  }
}
