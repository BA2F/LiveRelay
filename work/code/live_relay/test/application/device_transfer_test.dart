import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/transfer/transfer_index.dart';
import 'package:live_relay/application/transfer/transfer_models.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/transfer_medium.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/transfer/directory_transfer_medium.dart';

import '../support/verification_fakes.dart';

AppController controller(Directory root) => createAppController(
  root,
  NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
);

Future<void> addOriginal(AppController c, String name) => c.importOriginal(
  bytes: Uint8List.fromList(utf8.encode('fictional-$name')),
  originalName: name,
  mimeType: 'text/plain',
  mediaKind: BlobMediaKind.other,
);

Future<void> expectOriginal(AppController c, String name) async {
  final blob = c.blobs.singleWhere((b) => b.originalName == name);
  expect(utf8.decode(await c.readOriginal(blob.id)), 'fictional-$name');
}

VaultBlob blobFixture(String path, int byteLength) => VaultBlob(
  id: path.split('/').last,
  originalName: path,
  mediaKind: BlobMediaKind.other,
  mimeType: 'application/octet-stream',
  relativePath: path,
  byteLength: byteLength,
  sha256: 'fixture',
  createdAt: DateTime.utc(2026, 10, 13),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('planTransfer', () {
    const tag = '01234567';
    final volumeName = transferVolumeName(tag, 1);

    test('coverage is trusted only for the current snapshot and a present volume',
        () {
      final blobs = [
        blobFixture('blobs/a.blob', 100),
        blobFixture('blobs/b.blob', 200),
      ];
      final index = TransferIndex(
        snapshot: 's1',
        volumes: [
          TransferVolume(
            name: volumeName,
            bytes: 500,
            blobSizes: {'blobs/a.blob': 100 + blobCiphertextOverhead},
          ),
        ],
      );
      final present = [MediumEntry(name: volumeName, length: 500)];

      final stale = planTransfer(
        vaultTag: tag,
        snapshot: 's2',
        blobs: blobs,
        index: index,
        mediumEntries: present,
        payloadLimit: 1 << 20,
      );
      expect(stale.skippedBlobs, 0);
      expect(stale.warnings, isNotEmpty);
      expect(stale.volumes.single.blobSizes.keys, hasLength(2));

      final current = planTransfer(
        vaultTag: tag,
        snapshot: 's1',
        blobs: blobs,
        index: index,
        mediumEntries: present,
        payloadLimit: 1 << 20,
      );
      expect(current.skippedBlobs, 1);
      expect(current.reusable.single.name, volumeName);
      expect(current.volumes.single.name, transferVolumeName(tag, 2));
      expect(current.volumes.single.blobSizes.keys, ['blobs/b.blob']);

      final lost = planTransfer(
        vaultTag: tag,
        snapshot: 's1',
        blobs: blobs,
        index: index,
        mediumEntries: const [],
        payloadLimit: 1 << 20,
      );
      expect(lost.skippedBlobs, 0);
      expect(lost.reusable, isEmpty);
      expect(lost.volumes.single.blobSizes.keys, hasLength(2));
      final truncated = planTransfer(
        vaultTag: tag,
        snapshot: 's1',
        blobs: blobs,
        index: index,
        mediumEntries: [MediumEntry(name: volumeName, length: 400)],
        payloadLimit: 1 << 20,
      );
      expect(truncated.skippedBlobs, 0);
      expect(truncated.warnings, isNotEmpty);
    });

    test('volumes pack to the payload limit and oversized blobs ride alone',
        () {
      final plan = planTransfer(
        vaultTag: tag,
        snapshot: 's',
        blobs: [
          blobFixture('blobs/a.blob', 100),
          blobFixture('blobs/b.blob', 100),
          blobFixture('blobs/big.blob', 3000),
        ],
        index: null,
        mediumEntries: const [],
        payloadLimit: 500,
      );
      expect(plan.volumes, hasLength(2));
      expect(
        plan.volumes.first.blobSizes.keys,
        containsAll(['blobs/a.blob', 'blobs/b.blob']),
      );
      expect(plan.volumes.last.blobSizes.keys, ['blobs/big.blob']);
      expect(plan.volumes.first.name, transferVolumeName(tag, 1));
      expect(plan.volumes.last.name, transferVolumeName(tag, 2));
    });
  });

  test(
    'device transfer round trip reuses volumes and local originals',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      addTearDown(() => root.delete(recursive: true));
      final mediumDirectory = Directory('${root.path}/medium');
      await mediumDirectory.create(recursive: true);
      final medium = DirectoryTransferMedium(mediumDirectory);
      final a = controller(Directory('${root.path}/a'));
      final b = controller(Directory('${root.path}/b'));
      try {
        await a.initialize();
        final r1 = await a.generateRecovery();
        await a.setupModernVault(
          password: 'fictional-a-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await a.createCard(const CardDraft(title: '搬运卡片', content: 'fixture'));
        await addOriginal(a, 'one.txt');
        await addOriginal(a, 'two.txt');

        final first = await a.exportToMedium(medium, 'fictional-a-password');
        expect(first.skippedBlobs, 0);
        expect(first.writtenVolumes, hasLength(1));
        expect(first.indexPersisted, isTrue);
        final scan = await a.scanTransferMedium(medium);
        expect(scan.databases, hasLength(1));
        expect(scan.volumes, hasLength(1));
        expect(scan.unmatched, isEmpty);

        // Nothing new: the database package is rewritten, volumes are not.
        final again = await a.exportToMedium(medium, 'fictional-a-password');
        expect(again.writtenVolumes, isEmpty);
        expect(again.skippedBlobs, 2);

        // A fresh device receives the vault and its originals in one flow.
        await b.initialize();
        final firstImport = await b.importFromMedium(
          medium,
          databaseName: first.databaseName,
          credential: 'fictional-a-password',
        );
        expect(firstImport.requiresReset, isFalse);
        expect(firstImport.harvestedOriginals, 0);
        expect(firstImport.volumesConsumed, 1);
        expect(firstImport.remainingMissingOriginals, 0);
        expect(b.sessionState, VaultSessionState.unlocked);
        expect(b.cards.any((v) => v.title == '搬运卡片'), isTrue);
        await expectOriginal(b, 'one.txt');
        await expectOriginal(b, 'two.txt');

        // A adds one original: only the delta becomes a new volume.
        await addOriginal(a, 'three.txt');
        final delta = await a.exportToMedium(medium, 'fictional-a-password');
        expect(delta.skippedBlobs, 2);
        expect(delta.writtenVolumes, hasLength(1));
        expect(
          (await medium.list())
              .where((entry) => entry.name.contains('originals')),
          hasLength(2),
        );

        // B receives again: three originals are reused locally, the delta
        // volume completes the rest.
        final secondImport = await b.importFromMedium(
          medium,
          databaseName: delta.databaseName,
          credential: 'fictional-a-password',
        );
        expect(secondImport.harvestedOriginals, 2);
        expect(secondImport.volumesConsumed, 2);
        expect(secondImport.volumeErrors, isEmpty);
        expect(secondImport.remainingMissingOriginals, 0);
        await expectOriginal(b, 'three.txt');

        // B answers on the same medium; A reuses everything it already had.
        await addOriginal(b, 'four.txt');
        final back = await b.exportToMedium(medium, 'fictional-a-password');
        expect(back.skippedBlobs, 3);
        expect(back.writtenVolumes, hasLength(1));
        final answerImport = await a.importFromMedium(
          medium,
          databaseName: back.databaseName,
          credential: 'fictional-a-password',
        );
        expect(answerImport.harvestedOriginals, 3);
        expect(answerImport.volumesConsumed, 3);
        expect(answerImport.remainingMissingOriginals, 0);
        await expectOriginal(a, 'four.txt');
      } finally {
        await a.lock().catchError((_) {});
        await b.lock().catchError((_) {});
        a.dispose();
        b.dispose();
      }
    },
  );

  test('rotation invalidates medium coverage and re-exports originals', () async {
    final root = await Directory.systemTemp.createTemp('relay-transfer-');
    addTearDown(() => root.delete(recursive: true));
    final mediumDirectory = Directory('${root.path}/medium');
    await mediumDirectory.create(recursive: true);
    final medium = DirectoryTransferMedium(mediumDirectory);
    final a = controller(root);
    try {
      await a.initialize();
      final r1 = await a.generateRecovery();
      await a.setupModernVault(
        password: 'fictional-first-password',
        recoveryText: r1,
        recoveryConfirmation: r1,
      );
      await addOriginal(a, 'one.txt');
      final first = await a.exportToMedium(medium, 'fictional-first-password');
      expect(first.writtenVolumes, hasLength(1));

      final r2 = await a.generateRecovery();
      await a.configureSecurity(
        oldPassword: 'fictional-first-password',
        newPassword: 'fictional-second-password',
        recoveryText: r2,
        recoveryConfirmation: r2,
      );
      final rotated = await a.exportToMedium(medium, 'fictional-second-password');
      expect(rotated.skippedBlobs, 0);
      expect(rotated.writtenVolumes, hasLength(1));
      expect(rotated.warnings, isNotEmpty);
      expect(
        (await medium.list())
            .where((entry) => entry.name.contains('originals')),
        hasLength(2),
      );
    } finally {
      await a.lock().catchError((_) {});
      a.dispose();
    }
  });

  test(
    'all-factor vaults import the database first and volumes after the reset',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      addTearDown(() => root.delete(recursive: true));
      final mediumDirectory = Directory('${root.path}/medium');
      await mediumDirectory.create(recursive: true);
      final medium = DirectoryTransferMedium(mediumDirectory);
      final a = controller(Directory('${root.path}/a'));
      final b = controller(Directory('${root.path}/b'));
      try {
        await a.initialize();
        final r1 = await a.generateRecovery();
        await a.setupModernVault(
          password: 'fictional-setup-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        final file = Uint8List.fromList(List.filled(32, 21));
        final r2 = await a.generateRecovery();
        await a.configureSecurity(
          oldPassword: 'fictional-setup-password',
          newPassword: 'fictional-all-password',
          recoveryText: r2,
          recoveryConfirmation: r2,
          policy: 'all',
          newKeyFile: file,
        );
        await addOriginal(a, 'one.txt');
        final export = await a.exportToMedium(medium, r2);
        expect(export.writtenVolumes, hasLength(1));

        await b.initialize();
        final report = await b.importFromMedium(
          medium,
          databaseName: export.databaseName,
          credential: r2,
        );
        expect(report.requiresReset, isTrue);
        expect(report.volumesConsumed, 0);
        expect(report.pendingVolumes, hasLength(1));
        expect(report.remainingMissingOriginals, -1);
        expect(b.sessionState, VaultSessionState.recovering);
        expect(await b.missingOriginalCount(), 0);

        final r3 = await b.generateRecovery();
        await b.configureSecurity(
          oldPassword: '',
          newPassword: 'fictional-b-password',
          recoveryText: r3,
          recoveryConfirmation: r3,
        );
        expect(b.isUnlocked, isTrue);
        expect(await b.missingOriginalCount(), 1);
        final topUp = await b.importPendingVolumes(medium);
        expect(topUp.volumesConsumed, 1);
        expect(topUp.remainingMissingOriginals, 0);
        await expectOriginal(b, 'one.txt');
        file.fillRange(0, file.length, 0);
      } finally {
        await a.lock().catchError((_) {});
        await b.lock().catchError((_) {});
        a.dispose();
        b.dispose();
      }
    },
  );
}
