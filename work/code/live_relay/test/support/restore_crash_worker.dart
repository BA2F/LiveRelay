import 'dart:io';

import 'package:live_relay/infrastructure/backup/vault_restore_transaction.dart';

// A real subprocess exit deliberately skips Dart catch/finally handlers.
Future<void> main(List<String> arguments) async {
  final transaction = VaultRestoreTransaction(
    Directory(arguments[0]),
    checkpoint: (stage) async {
      if (stage == arguments[2]) exit(87);
    },
  );
  await transaction.install(
    Directory(arguments[1]),
    verifyInstalled: () async {},
    closeInstalled: () async {},
  );
  exit(0);
}
