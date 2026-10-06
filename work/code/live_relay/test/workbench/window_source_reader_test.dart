import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/preview_session.dart';
import 'package:live_relay/application/workbench/window_source_reader.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/widgets/local_media_preview.dart';

import '../support/verification_fakes.dart';

class PendingPreviewSession extends ChangeNotifier implements PreviewSession {
  final cleanups = <Future<void> Function()>{};
  @override
  bool get isUnlocked => true;
  @override
  void registerPreviewCleanup(Future<void> Function() cleanup) =>
      cleanups.add(cleanup);
  @override
  void unregisterPreviewCleanup(Future<void> Function() cleanup) =>
      cleanups.remove(cleanup);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'leaving a preview retains its pending cleanup and wipes late source bytes',
    (tester) async {
      final session = PendingPreviewSession();
      final pending = Completer<Uint8List>();
      await tester.pumpWidget(
        MaterialApp(
          home: LocalMediaPreview(
            controller: session,
            name: 'fixture.wav',
            video: false,
            readBytes: () => pending.future,
          ),
        ),
      );
      expect(session.cleanups, hasLength(1));
      await tester.pumpWidget(const SizedBox());
      expect(session.cleanups, hasLength(1));
      var stopped = false;
      final close = Future.wait([
        for (final cleanup in session.cleanups) cleanup(),
      ]).then((_) => stopped = true);
      await tester.pump();
      expect(stopped, isFalse);
      final bytes = Uint8List.fromList([1, 2, 3]);
      pending.complete(bytes);
      await tester.pump();
      await close;
      expect(bytes, [0, 0, 0]);
      expect(session.cleanups, isEmpty);
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
  test(
    'child permission is revoked before every pending preview cleanup finishes',
    () async {
      final session = DetachedPreviewSession();
      final decoder = Completer<void>();
      var stopped = 0, observedRevoked = false;
      session.addListener(() => observedRevoked = !session.isUnlocked);
      session.registerPreviewCleanup(() async {
        stopped++;
        await decoder.future;
      });
      var completed = false;
      final closed = session.revoke().then((_) => completed = true);
      expect(session.isUnlocked, isFalse);
      expect(observedRevoked, isTrue);
      expect(stopped, 1);
      expect(completed, isFalse);
      final again = session.revoke();
      decoder.complete();
      await closed;
      await again;
      expect(stopped, 1);
      expect(completed, isTrue);
      session.dispose();
    },
  );

  test(
    'only the active source view may read bounded unrecycled bytes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-window-source-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fixture-source',
          usesChinesePassphrase: false,
        );
        final fixture = Uint8List.fromList([1, 2, 3, 4]);
        final sourceCard = await c.importOriginal(
          bytes: Uint8List.fromList(fixture),
          originalName: 'fixture.wav',
          mimeType: 'audio/wav',
          mediaKind: BlobMediaKind.audio,
        );
        final id = c.blobs.single.id;
        var view = 'source/$id', active = true;
        final reader = WindowSourceReader(c);
        Future<Uint8List> read() =>
            reader.read(id: id, view: () => view, active: () => active);
        final bytes = await read();
        expect(bytes, fixture);
        bytes.fillRange(0, bytes.length, 0);
        view = 'originals';
        await expectLater(read(), throwsFormatException);
        view = 'source/$id';
        final changed = read();
        view = 'cards';
        await expectLater(changed, throwsFormatException);
        view = 'source/$id';
        active = false;
        await expectLater(read(), throwsFormatException);
        active = true;
        await c.trashCards([sourceCard.id], recycleUnsharedOriginals: true);
        await expectLater(read(), throwsFormatException);
        await c.importOriginal(
          bytes: Uint8List(WindowSourceReader.maxBytes + 1),
          originalName: 'large.wav',
          mimeType: 'audio/wav',
          mediaKind: BlobMediaKind.audio,
        );
        final large = c.blobs.firstWhere((b) => b.originalName == 'large.wav');
        view = 'source/${large.id}';
        await expectLater(
          reader.read(id: large.id, view: () => view, active: () => active),
          throwsFormatException,
        );
        await c.lock();
        await expectLater(read(), throwsFormatException);
      } finally {
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
