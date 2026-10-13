import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/storage/vault_failures.dart';
import 'package:live_relay/infrastructure/app_composition.dart';

import '../support/verification_fakes.dart';

AppController controller(Directory root) => createAppController(
  root,
  NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
);

Future<void> expectOriginal(
  AppController c,
  Directory root,
  String content, {
  String name = 'fixture.txt',
}) async {
  final blob = c.blobs.singleWhere((b) => b.originalName == name);
  expect(
    utf8.decode(await c.readOriginal(blob.id)),
    content,
  );
}

Future<Uint8List> blobBytes(Directory root, VaultBlob blob) =>
    File('${root.path}/live_relay/vault/${blob.relativePath}').readAsBytes();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'restoring a database package on the same device reuses matching originals',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      addTearDown(() => root.delete(recursive: true));
      final c = controller(root);
      try {
        await c.initialize();
        final r1 = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-transfer-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await c.createCard(
          const CardDraft(title: '搬运标记', content: 'fixture'),
        );
        await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional-original')),
          originalName: 'fixture.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );
        final pair = await c.exportSplitVault('fictional-transfer-password');
        expect((await c.inspectBackup(pair.database, 'fictional-transfer-password'))
            .requiresReset, isFalse);
        await c.restoreVault(pair.database, 'fictional-transfer-password');
        // Credentials travel with the vault: a satisfiable policy opens
        // straight, and the local originals are not owed again.
        expect(c.sessionState, VaultSessionState.unlocked);
        expect(await c.missingOriginalCount(), 0);
        expect(c.cards.any((v) => v.title == '搬运标记'), isTrue);
        await expectOriginal(c, root, 'fictional-original');
      } finally {
        await c.lock().catchError((_) {});
        c.dispose();
      }
    },
  );

  test(
    'a fresh device owes omitted originals and completes them byte-identically',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      addTearDown(() => root.delete(recursive: true));
      final rootA = Directory('${root.path}/a');
      final rootB = Directory('${root.path}/b');
      final rootC = Directory('${root.path}/c');
      final a = controller(rootA);
      final b = controller(rootB);
      final c = controller(rootC);
      try {
        await a.initialize();
        final r1 = await a.generateRecovery();
        await a.setupModernVault(
          password: 'fictional-source-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await a.createCard(const CardDraft(title: '源卡片', content: 'fixture'));
        for (final name in ['one.txt', 'two.txt']) {
          await a.importOriginal(
            bytes: Uint8List.fromList(utf8.encode('fictional-$name')),
            originalName: name,
            mimeType: 'text/plain',
            mediaKind: BlobMediaKind.other,
          );
        }
        final pair = await a.exportSplitVault('fictional-source-password');
        await b.initialize();
        await b.restoreVault(pair.database, 'fictional-source-password');
        expect(b.sessionState, VaultSessionState.unlocked);
        expect(b.cards.any((v) => v.title == '源卡片'), isTrue);
        expect(await b.missingOriginalCount(), 2);
        await expectLater(
          b.readOriginal(b.blobs.first.id),
          throwsStateError,
        );

        // A package from an unrelated vault cannot authenticate against this
        // ledger's recorded key.
        await c.initialize();
        final r2 = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-other-password',
          recoveryText: r2,
          recoveryConfirmation: r2,
        );
        await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('foreign')),
          originalName: 'foreign.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );
        final other = await c.exportSplitVault('fictional-other-password');
        await expectLater(
          b.importOriginalSupplement(other.attachments),
          throwsA(isA<LifeVaultArchiveException>()),
        );
        expect(await b.missingOriginalCount(), 2);

        await b.importOriginalSupplement(pair.attachments);
        expect(await b.missingOriginalCount(), 0);
        await expectOriginal(b, rootB, 'fictional-one.txt', name: 'one.txt');
        await expectOriginal(b, rootB, 'fictional-two.txt', name: 'two.txt');
        // Same key lineage: the verified ciphertext is copied byte for byte,
        // so descriptors stay stable for the next round trip.
        for (var i = 0; i < a.blobs.length; i++) {
          expect(
            await blobBytes(rootB, b.blobs[i]),
            await blobBytes(rootA, a.blobs[i]),
          );
        }
      } finally {
        await a.lock().catchError((_) {});
        await b.lock().catchError((_) {});
        await c.lock().catchError((_) {});
        a.dispose();
        b.dispose();
        c.dispose();
      }
    },
  );

  test(
    'rotation invalidates reuse and re-encrypts owed originals under the new key',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      addTearDown(() => root.delete(recursive: true));
      final c = controller(root);
      try {
        await c.initialize();
        final r1 = await c.generateRecovery();
        await c.setupModernVault(
          password: 'fictional-first-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await c.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional-original')),
          originalName: 'fixture.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );
        final pair = await c.exportSplitVault('fictional-first-password');

        final r2 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: 'fictional-first-password',
          newPassword: 'fictional-second-password',
          recoveryText: r2,
          recoveryConfirmation: r2,
        );
        // The rotated vault no longer matches the old descriptor, so the
        // original must travel again.
        await c.restoreVault(pair.database, 'fictional-first-password');
        expect(c.sessionState, VaultSessionState.unlocked);
        expect(await c.missingOriginalCount(), 1);

        final r3 = await c.generateRecovery();
        await c.configureSecurity(
          oldPassword: 'fictional-first-password',
          newPassword: 'fictional-third-password',
          recoveryText: r3,
          recoveryConfirmation: r3,
        );
        expect(await c.missingOriginalCount(), 1);
        final packaged = ZipDecoder()
            .decodeBytes(pair.attachments)
            .files
            .singleWhere((f) => f.name.startsWith('vault/blobs/'))
            .readBytes()!;
        await c.importOriginalSupplement(pair.attachments);
        expect(await c.missingOriginalCount(), 0);
        await expectOriginal(c, root, 'fictional-original');
        expect(
          await blobBytes(root, c.blobs.single),
          isNot(packaged),
        );
      } finally {
        await c.lock().catchError((_) {});
        c.dispose();
      }
    },
  );
}
