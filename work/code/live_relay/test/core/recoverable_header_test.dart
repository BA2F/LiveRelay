import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/core/storage/recoverable_file.dart';

void main() {
  test('oversized header is rejected before decoding and retained', () async {
    final root = await Directory.systemTemp.createTemp('relay-header-large-');
    addTearDown(() => root.delete(recursive: true));
    final manager = VaultKeyManager(root);
    await manager.headerFile.writeAsString('x' * (64 * 1024 + 1));
    await expectLater(manager.readMetadata(), throwsFormatException);
    expect(await manager.headerFile.length(), 64 * 1024 + 1);
  });
  test('lost canonical header recovers flushed predecessor and original key', () async {
    final root = await Directory.systemTemp.createTemp('relay-header-');
    addTearDown(() => root.delete(recursive: true));
    final original = VaultKeyManager(root);
    final key = await original.create(
      canonicalPassword: 'header-test-password',
      passwordKind: 'custom',
    );
    final interrupted = VaultKeyManager(
      root,
      writeCheckpoint: (stage) async {
        if (stage == 'pendingWritten') {
          // Emulate the gap of a platform that unlinks the rename destination.
          await original.headerFile.delete();
          throw const FileSystemException('injected interruption');
        }
      },
    );
    await expectLater(
      interrupted.setBiometricEnabled(true),
      throwsA(isA<FileSystemException>()),
    );
    final restarted = VaultKeyManager(root);
    expect((await restarted.readMetadata())!.biometricEnabled, isFalse);
    expect(await restarted.unlock('header-test-password'), key);
    key.fillRange(0, key.length, 0);
  });

  test(
    'uncommitted first header is recoverable without overwriting its key',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-header-');
      addTearDown(() => root.delete(recursive: true));
      final interrupted = VaultKeyManager(
        root,
        writeCheckpoint: (stage) async {
          if (stage == 'pendingWritten') {
            throw const FileSystemException('interrupted');
          }
        },
      );
      await expectLater(
        interrupted.create(
          canonicalPassword: 'first-header-password',
          passwordKind: 'custom',
        ),
        throwsA(isA<FileSystemException>()),
      );
      final restarted = VaultKeyManager(root);
      expect(await restarted.exists(), isTrue);
      expect(await restarted.unlock('first-header-password'), hasLength(32));
      await expectLater(
        restarted.create(
          canonicalPassword: 'different-new-password',
          passwordKind: 'custom',
        ),
        throwsStateError,
      );
    },
  );

  test(
    'malformed leftovers and symlink sidecars fail without deleting evidence',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-header-');
      addTearDown(() => root.delete(recursive: true));
      final manager = VaultKeyManager(root);
      final file = RecoverableFile(manager.headerFile);
      await file.pending.writeAsString('{partial');
      await expectLater(manager.exists(), throwsA(isA<FileSystemException>()));
      expect(await file.pending.readAsString(), '{partial');
      await file.pending.delete();
      final outside = File('${root.path}/outside')
        ..writeAsStringSync('untouched');
      await Link(file.previous.path).create(outside.path);
      await expectLater(manager.exists(), throwsA(isA<FileSystemException>()));
      expect(await outside.readAsString(), 'untouched');
    },
  );
}
