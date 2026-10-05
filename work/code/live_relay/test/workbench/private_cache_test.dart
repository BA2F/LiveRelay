import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/private_cache.dart';

void main() {
  test(
    'cache cleanup only removes app-owned contents and exact legacy root files',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-cache-fixture-',
      );
      try {
        final other = await Directory('${root.path}/other-app').create();
        final unrelated = await File('${other.path}/view-123.wav')
            .writeAsString('retain');
        final media = await File('${root.path}/unrelated.wav')
            .writeAsString('retain');
        final legacy = await File('${root.path}/speech-123.wav')
            .writeAsString('remove');
        final owned = await Directory('${root.path}/liverelay-private-cache')
            .create();
        final working = await File('${owned.path}/view-456.wav')
            .writeAsString('remove');
        await clearPrivateCache(root);
        expect(await unrelated.exists(), true);
        expect(await media.exists(), true);
        expect(await legacy.exists(), false);
        expect(await working.exists(), false);
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
