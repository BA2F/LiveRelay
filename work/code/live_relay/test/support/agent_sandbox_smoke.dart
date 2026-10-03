import 'dart:async';
import 'dart:io';

import 'package:live_relay/infrastructure/agent/linux_bash_command_provider.dart';

Future<void> main() async {
  final root = await Directory.systemTemp.createTemp(
    'liverelay-sandbox-verification-',
  );
  final provider = LinuxBashCommandProvider(
    resolveDirectory: () async => Directory('${root.path}/inputs'),
  );
  try {
    if (!await provider.available()) {
      throw StateError('Linux isolation is unavailable');
    }
    final session = await provider.open('[[SECRET_01]]\nfictional-input');
    try {
      final result = await session.run(
        'cat /input/input.txt; test ! -e /home && test ! -e /etc && test ! -e /run && test -z "\$API_KEY" && test -z "\$SSH_AUTH_SOCK" && printf "\\nprivate-roots-hidden\\n"; awk "END {print NR}" /proc/net/route; printf scratch > /work/result.txt; cat /work/result.txt',
      );
      if (result.exitCode != 0 ||
          !result.stdout.contains('private-roots-hidden\n1\nscratch')) {
        throw StateError('Filesystem/environment/network isolation failed');
      }
      final readOnly = await session.run('printf forbidden > /input/input.txt');
      if (readOnly.exitCode == 0) {
        throw StateError('Input unexpectedly writable');
      }
      if (!result.stdout.contains('[[SECRET_01]]')) {
        throw StateError('Redacted input not available');
      }
      try {
        await session.run('yes overflow');
        throw StateError('Oversized output unexpectedly accepted');
      } on FormatException catch (e) {
        if (!e.message.contains('64 KB')) rethrow;
      }
    } finally {
      await session.close();
    }
    final cancellation = Completer<void>();
    final cancelled = await provider.open(
      'fictional',
      whenCancelled: cancellation.future,
    );
    final pending = cancelled.run('sleep 30');
    final timer = Timer(
      const Duration(milliseconds: 250),
      cancellation.complete,
    );
    try {
      await pending;
      throw StateError('Cancellation unexpectedly returned a result');
    } on FormatException catch (e) {
      if (!e.message.contains('取消')) rethrow;
    } finally {
      timer.cancel();
      await cancelled.close();
    }
    stdout.writeln(
      'Linux sandbox: redacted input, hidden private roots/environment, no network routes, read-only input, temporary writes, output budget, cancellation passed.',
    );
  } finally {
    await root.delete(recursive: true);
  }
}
