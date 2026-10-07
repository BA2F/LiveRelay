import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/preview_session.dart';
import 'package:live_relay/presentation/workbench/detached_conversation_view.dart';

Map<String, Object?> data() => {
  'draft': 'fixture local text',
  'working': false,
  'marks': <String, Object?>{},
  'model': 'fixture-model',
  'models': [],
  'messages': [],
  'targets': [],
  'originals': [],
  'attachments': [],
  'conversationStamp': 'fixture-stamp',
};

void main() {
  testWidgets(
    'detached UI shows redacted consent; cancel is distinct from authorizing the prepared ticket',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = DetachedPreviewSession(), commands = <Map>[];
      final state = data();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetachedConversationView(
              data: state,
              session: session,
              act: (method, args) async =>
                  commands.add({'method': method, ...args}),
              request: (method, args) async => {
                'ticket': 'fixture-ticket',
                'text': '[[TURN1_SECRET_01]]',
                'history': 'fixture previous messages',
                'model': 'fixture-model',
                'host': 'verification.invalid',
                'targets': [],
                'attachments': [],
              },
              openSettings: () {},
              openSpeech: () {},
              openManual: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      expect(find.text('允许发送本轮对话？'), findsOneWidget);
      expect(find.text('[[TURN1_SECRET_01]]'), findsOneWidget);
      expect(commands, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(commands.single['method'], 'cancelSend');
      await tester.tap(find.text('发送'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('允许本次发送'));
      await tester.pumpAndSettle();
      expect(commands.last, {'method': 'send', 'ticket': 'fixture-ticket'});
      await tester.pumpWidget(const SizedBox());
      await session.revoke();
      session.dispose();
    },
  );

  testWidgets(
    'detached attachment preview unmount waits for its late scoped bytes and wipes them',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = DetachedPreviewSession(), read = Completer<Object?>();
      final state = data()
        ..['attachments'] = [
          {
            'id': 'fixture-file',
            'name': 'fixture.txt',
            'kind': 'text',
            'mime': 'text/plain',
            'size': 3,
            'frames': [],
            'card': null,
            'blob': null,
          },
        ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DetachedConversationView(
              data: state,
              session: session,
              act: (_, _) async {},
              request: (_, _) => read.future,
              openSettings: () {},
              openSpeech: () {},
              openManual: () {},
            ),
          ),
        ),
      );
      await tester.tap(find.text('fixture.txt'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      var cleaned = false;
      final cleanup = session.revoke().then((_) => cleaned = true);
      await tester.pump();
      expect(cleaned, false);
      final bytes = Uint8List.fromList([97, 98, 99]);
      read.complete({
        'id': 'fixture-file',
        'name': 'fixture.txt',
        'kind': 'text',
        'mime': 'text/plain',
        'bytes': bytes,
        'frames': [],
        'card': null,
        'blob': null,
      });
      await tester.pump();
      await cleanup;
      expect(bytes, [0, 0, 0]);
      expect(tester.takeException(), isNull);
      session.dispose();
    },
  );
}
