import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

void main() {
  test('lvault round trip authenticates and restores encrypted data', () async {
    final temporary = await Directory.systemTemp.createTemp('lvault-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = Directory('${temporary.path}/source');
    final keyManager = VaultKeyManager(source);
    final key = await keyManager.create(
      canonicalPassword: 'correct horse battery staple',
      passwordKind: 'custom',
    );
    final database = await AppDatabase.openEncrypted(
      vaultDirectory: source,
      masterKey: key,
    );
    final repository = SqliteVaultRepository(database);
    await repository.createCard(
      const CardDraft(
        title: 'archive-round-trip-marker',
        content: 'content-that-must-stay-encrypted',
        kind: CardKind.document,
        status: CardStatus.confirmed,
        tags: ['backup'],
      ),
      sourceKind: SourceKind.ownerInput,
      sourceLabel: 'test',
    );
    await repository.close();

    final service = LifeVaultArchiveService();
    final bytes = await service.create(
      vaultDirectory: source,
      masterKey: key,
      createdAt: DateTime.utc(2026, 9, 23),
    );
    expect(
      utf8.decode(bytes, allowMalformed: true),
      isNot(contains('content-that-must-stay-encrypted')),
    );

    final staged = await service.stage(
      archiveBytes: bytes,
      stagingParent: temporary,
    );
    final restoredKey = await VaultKeyManager(staged.directory)
        .unlock('correct horse battery staple');
    await service.verifyAuthentication(staged: staged, masterKey: restoredKey);
    final restoredDatabase = await AppDatabase.openEncrypted(
      vaultDirectory: staged.directory,
      masterKey: restoredKey,
    );
    final restoredRepository = SqliteVaultRepository(restoredDatabase);
    final cards = await restoredRepository.listCards();
    expect(cards.single.title, 'archive-round-trip-marker');
    await restoredRepository.close();

    key.fillRange(0, key.length, 0);
    restoredKey.fillRange(0, restoredKey.length, 0);
  });

  test('lvault rejects a payload changed without a new manifest', () async {
    final temporary = await Directory.systemTemp.createTemp('lvault-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = Directory('${temporary.path}/source');
    final key = await VaultKeyManager(source).create(
      canonicalPassword: 'another strong password',
      passwordKind: 'custom',
    );
    final database = await AppDatabase.openEncrypted(
      vaultDirectory: source,
      masterKey: key,
    );
    await database.close();
    final service = LifeVaultArchiveService();
    final bytes = await service.create(vaultDirectory: source, masterKey: key);

    final archive = ZipDecoder().decodeBytes(bytes);
    final changed = Archive();
    for (final entry in archive) {
      final content = entry.readBytes()!;
      if (entry.name == 'vault/vault.sqlite') {
        content[content.length ~/ 2] ^= 0xff;
      }
      changed.addFile(
        ArchiveFile.noCompress(entry.name, content.length, content),
      );
    }
    final tampered = ZipEncoder().encodeBytes(changed, level: 0);
    await expectLater(
      service.stage(
        archiveBytes: Uint8List.fromList(tampered),
        stagingParent: temporary,
      ),
      throwsA(isA<LifeVaultArchiveException>()),
    );
    key.fillRange(0, key.length, 0);
  });
}
