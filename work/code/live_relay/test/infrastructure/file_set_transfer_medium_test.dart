import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/transfer/directory_transfer_medium.dart';
import 'package:live_relay/infrastructure/transfer/file_set_transfer_medium.dart';

void main() {
  test('file-set medium lists, reads prefixes and saves through the hook',
      () async {
    final saved = <String, Uint8List>{};
    final bytes = Uint8List.fromList(List.generate(2048, (i) => i % 251));
    final medium = FileSetTransferMedium(
      [
        MediumSourceFile(
          name: 'LiveRelay-aaaaaaaa-database.lvault',
          length: bytes.length,
          readBytes: () async => Uint8List.fromList(bytes),
        ),
      ],
      save: (name, data) async {
        saved[name] = Uint8List.fromList(data);
        return true;
      },
    );
    final entries = await medium.list();
    expect(entries.single.name, 'LiveRelay-aaaaaaaa-database.lvault');
    expect(entries.single.length, bytes.length);
    expect(await medium.read(entries.single.name), bytes);
    final prefix = await medium.readPrefix(entries.single.name, 64);
    expect(prefix.length, 64);
    expect(prefix, bytes.sublist(0, 64));
    await medium.writeAtomic('out.lvault', Uint8List.fromList([1, 2, 3]));
    expect(saved['out.lvault'], [1, 2, 3]);
    await expectLater(
      FileSetTransferMedium(const [], save: (_, _) async => false).writeAtomic(
        'cancel.lvault',
        Uint8List.fromList([1]),
      ),
      throwsStateError,
    );
    await expectLater(medium.read('missing.lvault'), throwsStateError);
  });

  test('directory medium probes writability and writes atomically', () async {
    final directory = await Directory.systemTemp.createTemp('medium-probe-');
    addTearDown(() => directory.delete(recursive: true));
    final missing = Directory('${directory.path}/absent');
    expect(await DirectoryTransferMedium.probeWritable(directory), isTrue);
    expect(await DirectoryTransferMedium.probeWritable(missing), isFalse);
    final medium = DirectoryTransferMedium(directory);
    await medium.writeAtomic('pack.lvault', Uint8List.fromList([9, 9]));
    expect((await medium.list()).single.name, 'pack.lvault');
    expect(await File('${directory.path}/pack.lvault').readAsBytes(), [9, 9]);
    expect(
      (await directory.list().toList()).any((e) => e.path.endsWith('.tmp')),
      isFalse,
    );
    expect(() => medium.read('a/b'), throwsArgumentError);
    expect(await medium.readPrefix('pack.lvault', 1), [9]);
  });
}
