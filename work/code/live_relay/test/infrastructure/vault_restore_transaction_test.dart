import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/infrastructure/backup/vault_restore_transaction.dart';

Future<void> fixture(Directory directory, String marker) async {
  await directory.create(recursive: true);
  await File('${directory.path}/vault-header.json').writeAsString(marker);
  await File('${directory.path}/vault.sqlite').writeAsString('fixture-$marker');
}

void main() {
  for (final stage in [
    'journal.pendingWritten',
    'intentWritten',
    'incomingPrepared',
    'beforeOriginalMove',
    'originalMoved',
    'beforeIncomingInstall',
    'incomingInstalled',
    'installedVerified',
    'commit.pendingWritten',
  ]) {
    test(
      'restart after real subprocess termination at $stage retains original',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'relay-restore-crash-',
        );
        addTearDown(() => root.delete(recursive: true));
        final vault = Directory('${root.path}/vault');
        final staged = await root.createTemp('liverelay-restore-');
        await fixture(vault, 'old');
        await fixture(staged, 'new');
        final process = await Process.run('dart', [
          'run',
          'test/support/restore_crash_worker.dart',
          vault.path,
          staged.path,
          stage,
        ]);
        expect(
          process.exitCode,
          87,
          reason: '${process.stdout}\n${process.stderr}',
        );
        final restarted = VaultRestoreTransaction(vault);
        await restarted.recover();
        expect(
          await File('${vault.path}/vault-header.json').readAsString(),
          'old',
        );
        expect(
          await File('${vault.path}/vault.sqlite').readAsString(),
          'fixture-old',
        );
        expect(await restarted.recover(), isNull);
      },
    );
  }

  for (final stage in [
    'intentWritten',
    'originalMoved',
    'incomingInstalled',
    'committed',
  ]) {
    test(
      'first-use restore terminated at $stage recovers staged vault',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'relay-restore-first-',
        );
        addTearDown(() => root.delete(recursive: true));
        final vault = Directory('${root.path}/vault');
        final staged = await root.createTemp('liverelay-restore-');
        await fixture(staged, 'new');
        final process = await Process.run('dart', [
          'run',
          'test/support/restore_crash_worker.dart',
          vault.path,
          staged.path,
          stage,
        ]);
        expect(
          process.exitCode,
          87,
          reason: '${process.stdout}\n${process.stderr}',
        );
        await VaultRestoreTransaction(vault).recover();
        expect(
          await File('${vault.path}/vault.sqlite').readAsString(),
          'fixture-new',
        );
      },
    );
  }

  test('cleanup failure and restart preserve committed new vault and encrypted old copy', () async {
    final root = await Directory.systemTemp.createTemp('relay-cleanup-');
    addTearDown(() => root.delete(recursive: true));
    final vault = Directory('${root.path}/vault');
    final staged = await root.createTemp('liverelay-restore-');
    await fixture(vault, 'old');
    await fixture(staged, 'new');
    final transaction = VaultRestoreTransaction(
      vault,
      checkpoint: (stage) async {
        if (stage == 'beforeCleanup') {
          throw const FileSystemException('cleanup denied');
        }
      },
    );
    expect(
      await transaction.install(
        staged,
        verifyInstalled: () async {},
        closeInstalled: () async {},
      ),
      isNotNull,
    );
    // A legitimate header update after commit must not cause a rollback.
    await File('${vault.path}/vault-header.json')
        .writeAsString('changed-after-commit');
    await VaultRestoreTransaction(vault).recover();
    expect(
      await File('${vault.path}/vault.sqlite').readAsString(),
      'fixture-new',
    );
    final remnants = await root
        .list()
        .where((entry) => entry.path.contains('.rollback-'))
        .toList();
    expect(remnants, hasLength(1));
    expect(
      await File('${remnants.single.path}/vault.sqlite').readAsString(),
      'fixture-old',
    );
  });

  test('unverified or malformed paths never delete outside files or offer an empty vault', () async {
    final root = await Directory.systemTemp.createTemp(
      'relay-journal-invalid-',
    );
    addTearDown(() => root.delete(recursive: true));
    final vault = Directory('${root.path}/vault');
    final outside = File('${root.path}/outside')..writeAsStringSync('keep');
    final transaction = VaultRestoreTransaction(vault);
    await transaction.journal.writeAsString(
      jsonEncode({
        'version': 1,
        'operationId': 'a' * 32,
        'hadVault': true,
        'newHeader': 'x',
        'oldHeader': 'y',
        'stagingName': '../outside',
      }),
    );
    await expectLater(
      transaction.recover(),
      throwsA(isA<VaultRecoveryException>()),
    );
    expect(await outside.readAsString(), 'keep');
    expect(await transaction.journal.exists(), isTrue);
    await transaction.journal.delete();
    await Link(transaction.journal.path).create(outside.path);
    await expectLater(
      transaction.recover(),
      throwsA(isA<VaultRecoveryException>()),
    );
    expect(await outside.readAsString(), 'keep');
    await Link(transaction.journal.path).delete();
    await Directory('${vault.path}.rollback-orphan').create();
    await expectLater(
      transaction.recover(),
      throwsA(isA<VaultRecoveryException>()),
    );
    expect(await vault.exists(), isFalse);
  });
}
