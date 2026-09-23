import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';

void main() {
  test('wraps a random master key and rejects a wrong password', () async {
    final directory = await Directory.systemTemp.createTemp(
      'liverelay-key-test',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = VaultKeyManager(directory);

    final created = await manager.create(
      canonicalPassword: 'correct horse battery staple',
      passwordKind: 'custom',
    );
    final unlocked = await manager.unlock('correct horse battery staple');

    expect(unlocked, created);
    expect(created, hasLength(32));
    expect(
      () => manager.unlock('definitely-wrong-password'),
      throwsA(isA<VaultUnlockException>()),
    );
  });
}
