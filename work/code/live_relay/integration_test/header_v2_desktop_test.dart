import 'package:live_relay/infrastructure/backup/vault_restore_transaction.dart';

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/blob/encrypted_blob_store.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../test/support/verification_fakes.dart';

class UnusedLegacyBiometrics extends NoBiometrics {
  int saves = 0;
  int reads = 0;
  int clears = 0;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> saveMasterKey(Uint8List key) async {
    saves++;
  }

  @override
  Future<Uint8List?> readMasterKey() async {
    reads++;
    return Uint8List(32);
  }

  @override
  Future<void> clear() async {
    clears++;
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const project = String.fromEnvironment('HEADER_TEST_PROJECT');
  final fixtures = '$project/test/fixtures/header_v2';

  Future<VaultBlob> prepareVault(Directory vault, Map info) async {
    await vault.create(recursive: true);
    await File('$fixtures/custom.json').copy('${vault.path}/vault-header.json');
    final vmk = HeaderEncoding.decodeBinary(info['masterKey'], 32);
    try {
      final database = await AppDatabase.openEncrypted(
        vaultDirectory: vault,
        masterKey: vmk,
      );
      final repository = SqliteVaultRepository(database);
      try {
        await repository.createCard(
          const CardDraft(
            title: 'fictional-v2-card',
            content: 'fictional encrypted content',
            kind: CardKind.document,
            status: CardStatus.confirmed,
            tags: [],
          ),
        );
        final blob = await EncryptedBlobStore().write(
          vaultDirectory: vault,
          masterKey: vmk,
          clearBytes: Uint8List.fromList(utf8.encode('fictional-v2-original')),
          originalName: 'fixture.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        await repository.registerBlob(blob);
        return blob;
      } finally {
        await repository.close();
      }
    } finally {
      vmk.fillRange(0, vmk.length, 0);
    }
  }

  testWidgets(
    'recovery authenticates independent header before real SQLCipher/Blob access',
    (tester) async {
      expect(
        project,
        isNotEmpty,
        reason: 'Pass an isolated fixture project path',
      );
      final info = jsonDecode(
        await File('$fixtures/vectors.json').readAsString(),
      ) as Map;
      final root = await Directory.systemTemp.createTemp('v2-recovery-native-');
      final vault = Directory('${root.path}/vault');
      final blob = await prepareVault(vault, info);
      var opens = 0;
      final session = VaultSession(
        installationFactory: (directory) => VaultRestoreTransaction(directory),
        resolveDirectory: () async => vault,
        loadPassphraseCodec: () async => ChinesePassphraseCodec.parse(
          await File('$project/assets/wordlists/new-default-pinyin.wordlist')
              .readAsString(),
        ),
        biometricKeyStore: NoBiometrics(),
        blobStore: EncryptedBlobStore(),
        openRepository: (directory, key) async {
          opens++;
          return SqliteVaultRepository(
            await AppDatabase.openEncrypted(
              vaultDirectory: directory,
              masterKey: key,
            ),
          );
        },
      );
      try {
        await session.prepare();
        await session.inspect();
        await session.unlockWithRecovery(info['recoveryCredential'] as String);
        expect(
          (await session.repository.listCards()).map((c) => c.title),
          contains('fictional-v2-card'),
        );
        final clear = await session.readOriginal(blob);
        expect(utf8.decode(clear), 'fictional-v2-original');
        clear.fillRange(0, clear.length, 0);
        await session.close();
        final before = opens;
        await expectLater(
          session.unlockWithRecovery('invalid-fixture-recovery'),
          throwsA(isA<VaultUnlockException>()),
        );
        expect(opens, before);
        expect(session.state, VaultSessionState.locked);
        final file = File('${vault.path}/vault-header.json');
        final header =
            jsonDecode(await file.readAsString()) as Map<String, Object?>;
        final slot = ((header['branches'] as List)[0] as Map)['keySlot'] as Map;
        final tag = HeaderEncoding.decodeBinary(slot['mac'], 16)..[0] ^= 1;
        slot['mac'] = HeaderEncoding.binary(tag);
        await file.writeAsBytes(HeaderEncoding.encode(header));
        await expectLater(
          session.unlockWithRecovery(info['recoveryCredential'] as String),
          throwsA(isA<VaultUnlockException>()),
        );
        expect(opens, before);
        expect(() => session.repository, throwsStateError);
        expect(session.state, VaultSessionState.locked);
        await tester.pumpWidget(const SizedBox());
      } finally {
        await session.close();
        session.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  testWidgets(
    'v2 password works; unsupported export/device updates preserve session and never use old slot',
    (tester) async {
      final info = jsonDecode(
        await File('$fixtures/vectors.json').readAsString(),
      ) as Map;
      final password =
          (info['fixtures'] as List).first['canonicalPassword'] as String;
      final root = await Directory.systemTemp.createTemp('v2-password-native-');
      final vault = Directory('${root.path}/live_relay/vault');
      final blob = await prepareVault(vault, info);
      final bio = UnusedLegacyBiometrics();
      final c = createAppController(
        root,
        bio,
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      try {
        await c.initialize();
        expect(c.header!.formatVersion, 2);
        await expectLater(c.unlockWithBiometric(), throwsStateError);
        expect(bio.reads, 0);
        await c.unlockWithPassword(password);
        expect(c.isUnlocked, isTrue);
        final before = await File('${vault.path}/vault-header.json')
            .readAsBytes();
        await expectLater(
          c.enableBiometricWithPassword(password),
          throwsUnsupportedError,
        );
        await expectLater(c.setBiometricEnabled(false), throwsUnsupportedError);
        expect(bio.saves, 0);
        expect(bio.clears, 0);
        await expectLater(c.exportVault(password), throwsA(isA<Exception>()));
        expect(c.isUnlocked, isTrue);
        expect(
          c.cards.map((card) => card.title),
          contains('fictional-v2-card'),
        );
        expect(
          await File('${vault.path}/vault-header.json').readAsBytes(),
          before,
        );
        final clear = await c.readOriginal(blob.id);
        expect(utf8.decode(clear), 'fictional-v2-original');
        clear.fillRange(0, clear.length, 0);
        await c.lock();
        await tester.pumpWidget(const SizedBox());
      } finally {
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
