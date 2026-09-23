import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/blob/encrypted_blob_store.dart';

void main() {
  test('blob store encrypts on disk and decrypts with integrity', () async {
    final directory = await Directory.systemTemp.createTemp('blob-store-');
    addTearDown(() => directory.delete(recursive: true));
    final key = Uint8List.fromList(List<int>.generate(32, (index) => index));
    final clear = Uint8List.fromList(utf8.encode('private-original-marker'));
    final store = EncryptedBlobStore();

    final blob = await store.write(
      vaultDirectory: directory,
      masterKey: key,
      clearBytes: clear,
      originalName: '/unsafe/path/photo.jpg',
      mimeType: 'image/jpeg',
      mediaKind: BlobMediaKind.image,
    );
    final disk = await File('${directory.path}/${blob.relativePath}')
        .readAsBytes();
    expect(utf8.decode(disk, allowMalformed: true), isNot(contains('private')));
    expect(blob.originalName, 'photo.jpg');
    expect(
      await store.read(vaultDirectory: directory, masterKey: key, blob: blob),
      clear,
    );

    disk[disk.length - 1] ^= 0xff;
    await File('${directory.path}/${blob.relativePath}')
        .writeAsBytes(disk, flush: true);
    await expectLater(
      store.read(vaultDirectory: directory, masterKey: key, blob: blob),
      throwsA(isA<EncryptedBlobException>()),
    );
    key.fillRange(0, key.length, 0);
    clear.fillRange(0, clear.length, 0);
  });
}
