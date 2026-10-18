import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/storage/file_commit.dart';

/// The sandbox lives under %APPDATA% on Windows because that is the profile
/// location where a refused metadata rename first broke vault creation. A
/// profile that still carries the Encrypted (EFS) attribute exercises the
/// degraded commit here; one that does not takes the ordinary rename path.
/// Both outcomes must publish the same content, and the cross-volume case
/// below covers the degraded path deterministically.
Directory sandboxRoot() {
  final appData = Platform.environment['APPDATA'];
  final base = Platform.isWindows && appData != null
      ? Directory('$appData\\liverelay-commit-verification')
      : Directory.systemTemp;
  return base..createSync(recursive: true);
}

void main() {
  late Directory root;
  setUp(() async {
    root = await sandboxRoot().createTemp('commit-');
  });
  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('commit publishes a new file and replaces an existing one', () async {
    final target = File('${root.path}${Platform.pathSeparator}state.json');
    final first = File('${target.path}.tmp')
      ..writeAsStringSync('first', flush: true);
    await commitFile(first, target);
    expect(await target.readAsString(), 'first');
    expect(await first.exists(), isFalse);

    final second = File('${target.path}.tmp')
      ..writeAsStringSync('second', flush: true);
    await commitFile(second, target);
    expect(await target.readAsString(), 'second');
    expect(await second.exists(), isFalse);
  });

  test('commit publishes a staged directory tree and removes the staging', () async {
    final staging = Directory('${root.path}${Platform.pathSeparator}staged')
      ..createSync();
    Directory('${staging.path}${Platform.pathSeparator}nested').createSync();
    File('${staging.path}${Platform.pathSeparator}vault.sqlite')
        .writeAsStringSync('database', flush: true);
    File(
      '${staging.path}${Platform.pathSeparator}nested'
      '${Platform.pathSeparator}blob.bin',
    ).writeAsStringSync('blob', flush: true);
    final installed =
        Directory('${root.path}${Platform.pathSeparator}installed');

    await commitDirectory(staging, installed);

    expect(await staging.exists(), isFalse);
    expect(
      await File('${installed.path}${Platform.pathSeparator}vault.sqlite')
          .readAsString(),
      'database',
    );
    expect(
      await File(
        '${installed.path}${Platform.pathSeparator}nested'
        '${Platform.pathSeparator}blob.bin',
      ).readAsString(),
      'blob',
    );
  });

  test('commit refuses to overwrite an existing directory', () async {
    final staging = Directory('${root.path}${Platform.pathSeparator}staged')
      ..createSync();
    final installed = Directory('${root.path}${Platform.pathSeparator}installed')
      ..createSync();
    await expectLater(
      commitDirectory(staging, installed),
      throwsA(isA<FileSystemException>()),
    );
  });

  /// A rename across volumes is refused by the platform with
  /// `ERROR_NOT_SAME_DEVICE`, which is the same refusal an encrypted Windows
  /// profile reports. Point this at any writable directory on another volume:
  ///
  /// ```bash
  /// flutter test test/core/file_commit_test.dart \
  ///   --dart-define=LIVERELAY_SECOND_VOLUME=E:/LiveRelayProbe
  /// ```
  const secondVolume = String.fromEnvironment('LIVERELAY_SECOND_VOLUME');
  test(
    'commit degrades when the platform refuses the metadata rename',
    () async {
      final remote = await Directory(secondVolume).createTemp('commit-');
      addTearDown(() async {
        if (await remote.exists()) await remote.delete(recursive: true);
      });

      final refused = File(
        '${root.path}${Platform.pathSeparator}refused.tmp',
      )..writeAsStringSync('payload', flush: true);
      await expectLater(
        refused.rename('${remote.path}${Platform.pathSeparator}refused.json'),
        throwsA(
          isA<FileSystemException>().having(
            (error) => error.osError?.errorCode,
            'errorCode',
            Platform.isWindows ? 17 : 18,
          ),
        ),
      );

      final pending = File('${root.path}${Platform.pathSeparator}state.tmp')
        ..writeAsStringSync('payload', flush: true);
      final target = File(
        '${remote.path}${Platform.pathSeparator}state.json',
      );
      await commitFile(pending, target);
      expect(await target.readAsString(), 'payload');
      expect(await pending.exists(), isFalse);

      final staging = Directory('${root.path}${Platform.pathSeparator}staged')
        ..createSync();
      File('${staging.path}${Platform.pathSeparator}vault.sqlite')
          .writeAsStringSync('db', flush: true);
      final installed = Directory(
        '${remote.path}${Platform.pathSeparator}installed',
      );
      await commitDirectory(staging, installed);
      expect(
        await File('${installed.path}${Platform.pathSeparator}vault.sqlite')
            .readAsString(),
        'db',
      );
      expect(await staging.exists(), isFalse);
    },
    skip: secondVolume.isEmpty
        ? 'set LIVERELAY_SECOND_VOLUME to a writable directory on another volume'
        : null,
  );
}
