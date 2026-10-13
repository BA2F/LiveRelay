import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_header_v3.dart';
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
    // v1 originally derived the manifest key with an omitted/empty salt.
    // The Android-compatible zero salt must produce the identical v1 MAC.
    final legacyKey = await DartHkdf(hmac: DartHmac.sha256(), outputLength: 32)
        .deriveKey(
          secretKey: SecretKey(key),
          info: utf8.encode('LiveRelay/LifeVaultManifest/v1'),
        );
    final legacyMac = await DartHmac.sha256().calculateMac(
      staged.manifestBytes,
      secretKey: legacyKey,
    );
    expect(staged.manifestMac, legacyMac.bytes);
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

  test('attachments export keeps only the requested blob subset', () async {
    final temporary = await Directory.systemTemp.createTemp('lvault-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = Directory('${temporary.path}/source');
    final recovery = RecoveryCredential.generate();
    final key = Uint8List.fromList(List.generate(32, (i) => i + 1));
    try {
      final header = await VaultHeaderV3.create(
        password: 'subset strong password',
        masterKey: key,
        recovery: recovery,
      );
      await VaultKeyManager(source).writeV3(header);
      final database = await AppDatabase.openEncrypted(
        vaultDirectory: source,
        masterKey: key,
      );
      await database.close();
      final blobs = Directory('${source.path}/blobs');
      await blobs.create(recursive: true);
      await File('${blobs.path}/one.blob').writeAsBytes([1, 2, 3, 4]);
      await File('${blobs.path}/two.blob').writeAsBytes([5, 6, 7, 8]);

      final service = LifeVaultArchiveService();
      final bytes = await service.create(
        vaultDirectory: source,
        masterKey: key,
        kind: 'attachments',
        snapshotId: 'ff' * 16,
        blobPaths: {'blobs/one.blob'},
      );
      final staged = await service.stage(
        archiveBytes: bytes,
        stagingParent: temporary,
      );
      expect(staged.kind, 'attachments');
      expect(staged.omitted, isEmpty);
      expect(
        await File('${staged.directory.path}/blobs/one.blob').exists(),
        isTrue,
      );
      expect(
        await File('${staged.directory.path}/blobs/two.blob').exists(),
        isFalse,
      );
      expect(
        await File('${staged.directory.path}/vault-header.json').exists(),
        isTrue,
      );
      await expectLater(
        service.create(
          vaultDirectory: source,
          masterKey: key,
          kind: 'attachments',
          snapshotId: 'ff' * 16,
          blobPaths: {'blobs/gone.blob'},
        ),
        throwsA(isA<LifeVaultArchiveException>()),
      );
    } finally {
      recovery.dispose();
      key.fillRange(0, key.length, 0);
    }
  });

  test('container prefix inspection summarizes a real package', () async {
    final temporary = await Directory.systemTemp.createTemp('lvault-test-');
    addTearDown(() => temporary.delete(recursive: true));
    final source = Directory('${temporary.path}/source');
    final recovery = RecoveryCredential.generate();
    final key = Uint8List.fromList(List.generate(32, (i) => i + 7));
    try {
      final header = await VaultHeaderV3.create(
        password: 'prefix strong password',
        masterKey: key,
        recovery: recovery,
      );
      await VaultKeyManager(source).writeV3(header);
      final database = await AppDatabase.openEncrypted(
        vaultDirectory: source,
        masterKey: key,
      );
      await database.close();
      final service = LifeVaultArchiveService();
      final bytes = await service.create(
        vaultDirectory: source,
        masterKey: key,
        kind: 'database',
        snapshotId: 'ab' * 16,
      );
      final summary = service.inspectContainerPrefix(
        Uint8List.fromList(bytes.sublist(0, 64 * 1024)),
      );
      expect(summary, isNotNull);
      expect(summary!.formatVersion, 2);
      expect(summary.kind, 'database');
      expect(summary.snapshotId, 'ab' * 16);
      expect(summary.vaultId, header.vaultId);

      expect(
        service.inspectContainerPrefix(
          Uint8List.fromList(bytes.sublist(0, 40)),
        ),
        isNull,
      );
      expect(
        service.inspectContainerPrefix(Uint8List.fromList([1, 2, 3, 4])),
        isNull,
      );
      final foreign = Archive();
      foreign.addFile(ArchiveFile.string('other.txt', 'hello'));
      final foreignBytes = ZipEncoder().encodeBytes(foreign, level: 0);
      expect(
        service.inspectContainerPrefix(Uint8List.fromList(foreignBytes)),
        isNull,
      );
    } finally {
      recovery.dispose();
      key.fillRange(0, key.length, 0);
    }
  });
}
