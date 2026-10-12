import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/preview_session.dart';
import 'package:live_relay/presentation/widgets/local_pdf_preview.dart';

void main() {
  testWidgets('disposed PDF waits for pending reads and wipes late bytes', (
    tester,
  ) async {
    final session = PendingPreviewSession();
    final pending = Completer<Uint8List>();
    await tester.pumpWidget(
      MaterialApp(
        home: LocalPdfPreview(
          session: session,
          name: 'fictional.pdf',
          readBytes: () => pending.future,
        ),
      ),
    );
    expect(session.cleanups, hasLength(1));
    await tester.pumpWidget(const SizedBox());
    expect(session.cleanups, hasLength(1));
    var finished = false;
    final cleanup = Future.wait([for (final close in session.cleanups) close()])
        .then((_) => finished = true);
    await tester.pump();
    expect(finished, isFalse);
    final bytes = Uint8List.fromList([1, 2, 3]);
    pending.complete(bytes);
    await tester.pump();
    await cleanup;
    expect(bytes, [0, 0, 0]);
    expect(session.cleanups, isEmpty);
    expect(tester.takeException(), isNull);
    session.dispose();
  });

  testWidgets('oversized PDF is rejected and wiped before native parsing', (
    tester,
  ) async {
    final session = PendingPreviewSession();
    final bytes = Uint8List(LocalPdfPreview.maxBytes + 1)..[0] = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalPdfPreview(
          session: session,
          name: 'oversize.pdf',
          readBytes: () async => bytes,
        ),
      ),
    );
    await tester.pump();
    expect(find.text('PDF内嵌预览最多8 MB'), findsOneWidget);
    expect(bytes[0], 0);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(session.cleanups, isEmpty);
    session.dispose();
  });
}

class PendingPreviewSession extends ChangeNotifier implements PreviewSession {
  final cleanups = <Future<void> Function()>[];
  @override
  bool get isUnlocked => true;
  @override
  void registerPreviewCleanup(Future<void> Function() cleanup) =>
      cleanups.add(cleanup);
  @override
  void unregisterPreviewCleanup(Future<void> Function() cleanup) =>
      cleanups.remove(cleanup);
}
