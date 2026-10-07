import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/desktop_window_channel.dart';
import 'package:live_relay/application/workbench/window_projection.dart';

void main() {
  test(
    'Unix IPC preserves large binary/Unicode and concurrent request replies',
    () async {
      final root = await Directory.systemTemp.createTemp('liverelay-ipc-test-');
      final server = await ServerSocket.bind(
        InternetAddress(
          '${root.path}/test.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      final accepted = Completer<LocalWindowChannel>();
      final replyBuffers = <Uint8List>[];
      final deniedBuffers = <Uint8List>[];
      server.listen((socket) {
        final peer = LocalWindowChannel(socket);
        peer.setMethodCallHandler((call) async {
          if (call.method == 'denied') {
            deniedBuffers.add((call.arguments as Map)['bytes'] as Uint8List);
            throw PlatformException(code: 'DENIED');
          }
          replyBuffers.add((call.arguments as Map)['bytes'] as Uint8List);
          return call.arguments;
        });
        accepted.complete(peer);
      });
      final socket = await Socket.connect(
        InternetAddress(
          '${root.path}/test.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      final client = LocalWindowChannel(socket), peer = await accepted.future;
      try {
        final payload = Uint8List.fromList(
          List.generate(400000, (i) => i % 256),
        );
        final futures = [
          for (var i = 0; i < 12; i++)
            client.invokeMethod<Map>('echo', {
              'index': i,
              'text': '虚构资料 $i',
              'bytes': payload,
            }),
        ];
        final replies = await Future.wait(futures);
        for (var i = 0; i < replies.length; i++) {
          expect(replies[i]!['index'], i);
          expect(replies[i]!['text'], '虚构资料 $i');
          expect(replies[i]!['bytes'], payload);
        }
        expect(replyBuffers, hasLength(12));
        expect(replyBuffers.every((b) => b.every((v) => v == 0)), isTrue);
        await expectLater(
          client.invokeMethod('denied', {'bytes': payload}),
          throwsA(isA<PlatformException>()),
        );
        expect(deniedBuffers.single.every((b) => b == 0), true);
        expect(payload.any((b) => b != 0), true);
      } finally {
        client.close();
        peer.close();
        await server.close();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'oversized IPC frame is disconnected before allocating its body',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-ipc-bound-',
      );
      final server = await ServerSocket.bind(
        InternetAddress(
          '${root.path}/test.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      final accepted = Completer<LocalWindowChannel>();
      server.listen((socket) => accepted.complete(LocalWindowChannel(socket)));
      final socket = await Socket.connect(
        InternetAddress(
          '${root.path}/test.sock',
          type: InternetAddressType.unix,
        ),
        0,
      );
      final peer = await accepted.future, closed = Completer<void>();
      socket.listen((_) {}, onDone: closed.complete);
      try {
        socket.add(
          (ByteData(4)..setUint32(0, LocalWindowChannel.maxFrame + 1)).buffer
              .asUint8List(),
        );
        await closed.future.timeout(const Duration(seconds: 2));
      } finally {
        socket.destroy();
        peer.close();
        await server.close();
        await root.delete(recursive: true);
      }
    },
  );
  test('window geometry accepts monitor coordinates and rejects invalid/unbounded dimensions', () {
    expect(
      windowBounds({'x': -1920, 'y': 20, 'width': 800, 'height': 600})!['x'],
      -1920.0,
    );
    expect(
      windowBounds({'x': 0, 'y': 0, 'width': double.infinity, 'height': 600}),
      isNull,
    );
    expect(
      windowBounds({'x': 100001, 'y': 0, 'width': 800, 'height': 600}),
      isNull,
    );
    expect(windowBounds({'x': 0, 'y': 0, 'width': 20, 'height': 600}), isNull);
    expect(detachableView('passwords'), false);
    expect(detachableView('card/fixture-uuid/1'), true);
  });
}
