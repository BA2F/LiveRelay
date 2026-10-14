import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/transfer/webdav_transfer_medium.dart';

/// Live round trip against a real copyparty instance. Opt-in so the ordinary
/// suite stays self-contained; run with e.g.:
///   flutter test test/infrastructure/webdav_live_copyparty_test.dart \
///     --dart-define=COPYPARTY_URL=http://127.0.0.1:3923/alice/ \
///     --dart-define=COPYPARTY_USER=alice \
///     --dart-define=COPYPARTY_PASS=alicepass
void main() {
  const url = String.fromEnvironment('COPYPARTY_URL');
  const user = String.fromEnvironment('COPYPARTY_USER');
  const pass = String.fromEnvironment('COPYPARTY_PASS');

  test(
    'lives through put, list, ranged read, overwrite and move on copyparty',
    skip: url.isEmpty ? '需要 COPYPARTY_URL 等 dart-define' : null,
    () async {
      final medium = WebDavTransferMedium(
        baseUrl: Uri.parse(url),
        username: user,
        password: pass,
      );
      final database = 'LiveRelay-livetest-database.lvault';
      final volume = 'LiveRelay-livetest-originals-0001.lvault';
      final first = Uint8List.fromList(
        List.generate(5000, (i) => (i * 7) % 251),
      );
      final second = Uint8List.fromList(
        List.generate(9000, (i) => (i * 11) % 251),
      );

      await medium.writeAtomic(database, first);
      await medium.writeAtomic(volume, second);

      final entries = await medium.list();
      final names = {for (final entry in entries) entry.name: entry.length};
      expect(names[database], first.length);
      expect(names[volume], second.length);

      final prefix = await medium.readPrefix(database, 512);
      expect(prefix, first.sublist(0, 512));
      expect(await medium.read(volume), second);

      // Overwrite the database package (the per-trip rewrite path).
      final grown = Uint8List.fromList([...first, ...first]);
      await medium.writeAtomic(database, grown);
      expect(await medium.read(database), grown);
      expect(
        (await medium.list()).where((e) => e.name.endsWith('.tmp')),
        isEmpty,
      );

      // The port has no delete on purpose; the two deterministic test files
      // stay on the medium and are overwritten by the next run.
    },
  );
}
