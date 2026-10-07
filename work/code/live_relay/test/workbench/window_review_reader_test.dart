import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/preview_session.dart';
import 'package:live_relay/application/workbench/window_review_reader.dart';
import 'package:live_relay/core/ai/conversation_attachment.dart';
import 'package:live_relay/core/ai/review_source.dart';
import 'package:live_relay/presentation/workbench/review_source_view.dart';

ReviewSource fixture({bool large = false}) => ReviewSource(
  reviewId: 'fixture-review',
  providerLabel: 'fixture service',
  confirmedAt: DateTime.utc(2026, 10, 7),
  reply: '完整模型答复',
  inputs: [
    for (var input = 0; input < (large ? 3 : 1); input++)
      ReviewSourceInput('中文🙂确认依据', [
        for (var a = 0; a < (large ? 3 : 1); a++)
          ConversationAttachment.read(
            'fixture.pdf',
            Uint8List.fromList([
              ...ascii.encode('%PDF-'),
              ...List.filled(large ? 1500000 : 10, 42),
            ]),
          ),
      ]),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'records larger than an IPC frame survive scoped sequential chunks',
    () async {
      var loads = 0, view = 'card-a';
      final reader = WindowReviewReader(
        allowed: (id) => id == view,
        load: (_) async {
          loads++;
          return fixture(large: true);
        },
      );
      final assembled = BytesBuilder(copy: false);
      var offset = 0;
      int? generation;
      try {
        while (true) {
          final result = await reader.readChunk('card-a', offset);
          generation ??= result['generation'] as int;
          expect(result['generation'], generation);
          final bytes = result['bytes'] as Uint8List;
          expect(
            bytes.length,
            lessThanOrEqualTo(WindowReviewReader.chunkBytes),
          );
          assembled.add(Uint8List.fromList(bytes));
          offset += bytes.length;
          bytes.fillRange(0, bytes.length, 0);
          if (offset == result['length']) break;
          if (offset == WindowReviewReader.chunkBytes) {
            await expectLater(
              reader.readChunk('card-b', offset),
              throwsFormatException,
            );
            await expectLater(
              reader.readChunk('card-a', 0),
              throwsFormatException,
            );
          }
        }
        expect(offset, greaterThan(16 * 1024 * 1024));
        expect(loads, 1);
        final bytes = assembled.takeBytes();
        final source = ReviewSource.decode(utf8.decode(bytes));
        bytes.fillRange(0, bytes.length, 0);
        expect(source.inputs, hasLength(3));
        expect(source.inputs.first.text, '中文🙂确认依据');
        expect(source.inputs.last.attachments.last.bytes.last, 42);
        source.wipe();
        view = 'elsewhere';
        await expectLater(reader.readChunk('card-a', 0), throwsFormatException);
      } finally {
        await reader.clear();
      }
    },
  );

  test(
    'revocation waits for pending evidence and wipes its attachment bytes',
    () async {
      final pending = Completer<ReviewSource?>();
      var active = true;
      final reader = WindowReviewReader(
        load: (_) => pending.future,
        allowed: (_) => active,
      );
      final read = reader.readChunk('card-a', 0);
      final rejected = expectLater(read, throwsFormatException);
      active = false;
      var cleared = false;
      final closing = reader.clear().then((_) => cleared = true);
      await Future<void>.delayed(Duration.zero);
      expect(cleared, false);
      final evidence = fixture();
      final bytes = evidence.inputs.single.attachments.single.bytes;
      pending.complete(evidence);
      await rejected;
      await closing;
      expect(bytes.every((b) => b == 0), true);
    },
  );

  test(
    'failed reads can retry; records missing on old cards remain absent',
    () async {
      var fails = true;
      final reader = WindowReviewReader(
        allowed: (_) => true,
        load: (_) async {
          if (fails) throw StateError('fixture transient failure');
          return null;
        },
      );
      await expectLater(reader.readChunk('card-a', 0), throwsStateError);
      fails = false;
      expect((await reader.readChunk('card-a', 0))['length'], 0);
      await reader.clear();
    },
  );

  testWidgets('shared review view wipes a late read after leaving the window', (
    tester,
  ) async {
    final session = DetachedPreviewSession();
    final pending = Completer<ReviewSource?>();
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewSourceView(
          session: session,
          loadSource: (_) => pending.future,
          cardTitle: (_) => 'fixture card',
          cardId: 'card-a',
          onCard: (_) {},
          onOriginal: (_) {},
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox());
    var revoked = false;
    final revoke = session.revoke().then((_) => revoked = true);
    await tester.pump();
    expect(revoked, false);
    final evidence = fixture();
    final bytes = evidence.inputs.single.attachments.single.bytes;
    pending.complete(evidence);
    await tester.pump();
    await revoke;
    expect(bytes.every((b) => b == 0), true);
    expect(tester.takeException(), isNull);
    session.dispose();
  });
}
