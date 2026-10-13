import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';

import '../test/support/verification_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'SQLCipher schema4 upgrades local metadata without changing records',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'local-schema-native-',
      );
      final vault = Directory('${root.path}/vault'),
          key = Uint8List.fromList(List.filled(32, 42));
      try {
        var db = await AppDatabase.openEncrypted(
          vaultDirectory: vault,
          masterKey: key,
        );
        await db.customStatement(
          "INSERT INTO vault_local_state(name,value) VALUES ('fixture','old')",
        );
        await db.customStatement('DROP TABLE vault_local_state');
        await db.customStatement('PRAGMA user_version = 4');
        await db.close();
        db = await AppDatabase.openEncrypted(
          vaultDirectory: vault,
          masterKey: key,
        );
        await db.customStatement(
          "INSERT INTO vault_local_state(name,value) VALUES ('fixture','migrated')",
        );
        expect(
          (await db
                  .customSelect(
                    "SELECT value FROM vault_local_state WHERE name='fixture'",
                  )
                  .getSingle())
              .data['value'],
          'migrated',
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle())
              .data
              .values
              .single,
          5,
        );
        await db.close();
        await tester.pumpWidget(const SizedBox());
      } finally {
        key.fillRange(0, key.length, 0);
        await root.delete(recursive: true);
      }
    },
  );
  testWidgets(
    'native v3 rekey + limited recovery + split restore and supplement keep complete encrypted history',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'local-completion-native-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final file = Uint8List.fromList(List.filled(32, 73));
      try {
        await c.initialize();
        expect(c.sessionState, VaultSessionState.needsSetup);
        final r1 = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-first-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await c.createCard(const CardDraft(title: '保留历史', content: 'first'));
        final id = c.cards.single.id;
        await c.updateCard(
          id,
          const CardDraft(title: '保留历史', content: 'second'),
        );
        await c.saveCredential(
          const CredentialDraft(
            title: 'fictional account',
            username: 'fixture',
            secret: 'fixture-secret',
          ),
        );
        final imported = await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional-original')),
          originalName: 'fixture.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.document,
        );
        final blob = c.blobs.single;
        final manager = VaultKeyManager(
          Directory('${root.path}/live_relay/vault'),
        );
        final oldKey = await manager.unlock('fictional-first-password');
        final before = await File(
          '${root.path}/live_relay/vault/${blob.relativePath}',
        ).readAsBytes();
        final r2 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: 'fictional-first-password',
          newPassword: 'fictional-second-password',
          recoveryText: r2,
          recoveryConfirmation: r2,
          policy: 'all',
          newKeyFile: file,
        );
        expect(c.header!.formatVersion, 3);
        expect(c.header!.dailyPolicy, 'all');
        expect(
          await File('${root.path}/live_relay/vault/${blob.relativePath}')
              .readAsBytes(),
          isNot(before),
        );
        await expectLater(
          manager.unlockWithRecovery(r1),
          throwsA(isA<VaultUnlockException>()),
        );
        expect(
          utf8.decode(await c.readOriginal(blob.id)),
          'fictional-original',
        );
        await c.lock();
        await expectLater(
          c.unlockWithPassword('fictional-second-password'),
          throwsA(isA<VaultUnlockException>()),
        );
        expect(c.sessionState, VaultSessionState.locked);
        await expectLater(
          AppDatabase.openEncrypted(
            vaultDirectory: Directory('${root.path}/live_relay/vault'),
            masterKey: oldKey,
          ),
          throwsA(anything),
        );
        oldKey.fillRange(0, oldKey.length, 0);
        await c.unlockDaily(
          password: 'fictional-second-password',
          keyFile: file,
        );
        final pair = await c.exportSplitVault(r2);
        final other = await c.exportSplitVault(r2);
        final preview = await c.inspectBackup(pair.database, r2);
        expect(preview.requiresReset, true);
        expect(preview.missingOriginals, 1);
        await c.restoreVault(pair.database, r2);
        expect(c.sessionState, VaultSessionState.recovering);
        expect(c.cards, isEmpty);
        final r3 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: '',
          newPassword: 'fictional-third-password',
          recoveryText: r3,
          recoveryConfirmation: r3,
        );
        expect(c.isUnlocked, true);
        expect(c.cards.map((v) => v.id), containsAll([id, imported.id]));
        expect(await c.missingOriginalCount(), 1);
        await expectLater(c.readOriginal(blob.id), throwsStateError);
        // Stable snapshots: both exports from the same key generation carry
        // the same pairing id, so the second one also completes the restore.
        await c.importOriginalSupplement(other.attachments);
        expect(await c.missingOriginalCount(), 0);
        await expectLater(
          c.importOriginalSupplement(pair.attachments),
          throwsStateError,
        );
        expect(
          utf8.decode(await c.readOriginal(blob.id)),
          'fictional-original',
        );
        expect((await c.cardHistory(id)).map((r) => r.content), [
          'second',
          'first',
        ]);
        expect(c.credentials.single.secret, 'fixture-secret');
        await expectLater(
          manager.unlockWithRecovery(r2),
          throwsA(isA<VaultUnlockException>()),
        );
        final full = await c.exportVault('fictional-third-password');
        final check = await c.inspectBackup(full, r3);
        expect(check.missingOriginals, 0);
        await c.beginRecovery(r3);
        expect(c.sessionState, VaultSessionState.recovering);
        expect(c.credentials, isEmpty);
        final r4 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: '',
          newPassword: 'fictional-final-password',
          recoveryText: r4,
          recoveryConfirmation: r4,
        );
        expect(c.isUnlocked, true);
        expect(c.credentials.single.secret, 'fixture-secret');
        await tester.pumpWidget(const SizedBox());
      } finally {
        await c.lock();
        c.dispose();
        await root.delete(recursive: true);
        file.fillRange(0, file.length, 0);
      }
    },
  );
}
