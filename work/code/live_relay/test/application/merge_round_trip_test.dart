import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/device_transfer_service.dart';
import 'package:live_relay/application/vault_backup_service.dart';
import 'package:live_relay/application/vault_merge_service.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/vault_merge.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';
import 'package:live_relay/infrastructure/backup/vault_restore_transaction.dart';
import 'package:live_relay/infrastructure/blob/encrypted_blob_store.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';
import 'package:live_relay/infrastructure/transfer/directory_transfer_medium.dart';

import '../support/verification_fakes.dart';

const _password = 'fictional-merge-password';

/// The engine stack the composition wires for one device, built without the
/// presentation controller so the merge engine can be driven directly.
class Device {
  Device(this.root)
    : session = VaultSession(
        installationFactory: (directory) => VaultRestoreTransaction(directory),
        resolveDirectory: () async =>
            Directory('${root.path}/live_relay/vault'),
        loadPassphraseCodec: () async => ChinesePassphraseCodec.parse(
          await File('assets/wordlists/new-default-pinyin.wordlist')
              .readAsString(),
        ),
        openRepository: (directory, key) async => SqliteVaultRepository(
          await AppDatabase.openEncrypted(
            vaultDirectory: directory,
            masterKey: key,
          ),
        ),
        biometricKeyStore: NoBiometrics(),
        blobStore: EncryptedBlobStore(),
      ),
      archive = LifeVaultArchiveService();

  final Directory root;
  final VaultSession session;
  final LifeVaultArchiveService archive;
  late final VaultBackupService backup = VaultBackupService(
    session: session,
    archive: archive,
    restoreTransaction: () => VaultRestoreTransaction(session.directory),
  );
  late final VaultMergeService merge = VaultMergeService(
    session: session,
    archive: archive,
    backup: backup,
    restoreTransaction: () => VaultRestoreTransaction(session.directory),
  );
  late final DeviceTransferService transfer = DeviceTransferService(
    backup: backup,
    archive: archive,
  );
  int refreshes = 0, clears = 0;

  Future<void> refresh() async {
    refreshes++;
  }

  void clearData() {
    clears++;
  }

  Future<void> createNewVault() async {
    await session.prepare();
    await session.inspect();
    await session.createModern(
      password: _password,
      recovery: RecoveryCredential.generate(),
    );
  }

  Future<void> dispose() async {
    await session.close().catchError((_) {});
    session.dispose();
  }
}

/// Writes the encrypted file and registers only its row: the caller decides
/// how the original is referenced (the 附件直加 primitive).
Future<VaultBlob> addOriginal(
  VaultSession session,
  String name,
  String content,
) async {
  final blob = await session.writeOriginal(
    bytes: Uint8List.fromList(utf8.encode(content)),
    originalName: name,
    mimeType: 'text/plain',
    mediaKind: BlobMediaKind.other,
  );
  await session.repository.registerBlobRow(blob);
  return blob;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'two copies of one vault diverge, merge and converge on both sides',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-merge-');
      addTearDown(() => root.delete(recursive: true));
      final mediumDirectory = Directory('${root.path}/medium');
      await mediumDirectory.create(recursive: true);
      final medium = DirectoryTransferMedium(mediumDirectory);
      final a = Device(Directory('${root.path}/a'));
      final b = Device(Directory('${root.path}/b'));
      try {
        // A seeds one card with one original.
        await a.createNewVault();
        final base = await a.session.repository.createCard(
          const CardDraft(title: '基地卡片', content: 'v1'),
        );
        final blobA = await addOriginal(a.session, 'a.txt', 'fictional-a');
        await a.session.repository.setCardOriginals(base.id, [blobA.id]);
        final oneWay = await a.session.repository.createCard(
          const CardDraft(title: '单向卡片', content: 'v1'),
        );
        final doomed = await a.session.repository.createCard(
          const CardDraft(title: '将被删除', content: 'v1'),
        );
        final exportA = await a.backup.exportTransferToMedium(
          medium,
          _password,
          refreshUnlockedData: a.refresh,
        );
        expect(exportA.writtenVolumes, hasLength(1));

        // B becomes a second copy of the same vault lineage.
        await b.session.prepare();
        await b.session.inspect();
        await b.backup.restore(
          await medium.read(exportA.databaseName),
          _password,
          clearUnlockedData: b.clearData,
          refreshUnlockedData: b.refresh,
        );
        expect(b.session.state, VaultSessionState.unlocked);
        expect(
          (await b.transfer.importPendingVolumes(medium))
              .remainingMissingOriginals,
          0,
        );

        // Identical content merges to nothing.
        final exportB0 = await b.backup.exportTransferToMedium(
          medium,
          _password,
          refreshUnlockedData: b.refresh,
        );
        final identical = await a.merge.mergeFromMedium(
          medium,
          databaseName: exportB0.databaseName,
          credential: _password,
          clearUnlockedData: a.clearData,
          refreshUnlockedData: a.refresh,
        );
        expect(identical.mergedCards, 0);
        expect(identical.conflicts, isEmpty);
        expect(identical.remainingMissingOriginals, 0);

        // Diverge: both edit the base card; each creates its own card and B
        // adds an original that only exists on B.
        await a.session.repository.updateCard(
          base.id,
          const CardDraft(title: '基地卡片', content: 'A 修改'),
          changeNote: 'A 编辑',
        );
        final aOnly = await a.session.repository.createCard(
          const CardDraft(title: 'A 独有', content: 'a-only'),
        );
        await a.session.repository.updateCard(
          oneWay.id,
          const CardDraft(title: '单向卡片', content: 'A 单向修改'),
          changeNote: 'A 编辑',
        );
        await b.session.repository.updateCard(
          base.id,
          const CardDraft(title: '基地卡片', content: 'B 修改'),
          changeNote: 'B 编辑',
        );
        final bOnly = await b.session.repository.createCard(
          const CardDraft(title: 'B 独有', content: 'b-only'),
        );
        final blobB = await addOriginal(b.session, 'b.txt', 'fictional-b');
        await b.session.repository.setCardOriginals(bOnly.id, [blobB.id]);
        await b.session.repository.setCardReferences(bOnly.id, [base.id]);
        await b.session.repository.trashCard(doomed.id);
        final exportB = await b.backup.exportTransferToMedium(
          medium,
          _password,
          refreshUnlockedData: b.refresh,
        );
        expect(exportB.writtenVolumes, hasLength(1));

        // A merges B's package: the fork keeps A's version, B's card comes in
        // and B's original arrives through the paired volume.
        final report = await a.merge.mergeFromMedium(
          medium,
          databaseName: exportB.databaseName,
          credential: _password,
          clearUnlockedData: a.clearData,
          refreshUnlockedData: a.refresh,
        );
        expect(report.importedCards, 1);
        expect(report.fastForwardedCards, 0);
        expect(report.forkedCards, 1);
        expect(report.adoptedDeletions, 1);
        expect(report.conflicts, hasLength(1));
        expect(report.conflicts.single.cardId, base.id);
        expect(report.conflicts.single.kind, MergeConflictKind.fork);
        expect(report.owedBlobs, 1);
        expect(report.remainingMissingOriginals, 0);
        expect(report.volumesConsumed, greaterThanOrEqualTo(1));
        expect(report.unmergedCategories, isNotEmpty);

        final repoA = a.session.repository;
        expect((await repoA.getCard(base.id))!.content, 'A 修改');
        // 本机未改动的卡片采用对方的删除。
        expect(
          (await repoA.listCards(recycled: true)).map((c) => c.id),
          contains(doomed.id),
        );
        // 引用 union：随导入卡片带入的引用成立。
        expect(
          (await repoA.cardReferences()).any(
            (r) => r.from == bOnly.id && r.to == base.id,
          ),
          isTrue,
        );
        expect(
          report.referenceChanges.map((c) => c.cardId),
          contains(bOnly.id),
        );
        final ascending = (await repoA.cardHistory(base.id)).reversed.toList();
        // [创建, 引用原件, A 编辑, 对方分叉段, 本机 reaffirm]
        expect(ascending.map((r) => r.number), [1, 2, 3, 4, 5]);
        expect(ascending[3].content, 'B 修改');
        expect(ascending[3].changeNote, startsWith('来自另一台设备：'));
        expect(ascending[4].content, 'A 修改');
        expect(ascending[4].changeNote, '合并：暂保留本机版');
        expect(await repoA.getCard(aOnly.id), isNotNull);
        expect(await repoA.getCard(bOnly.id), isNotNull);

        final bSources = await repoA.currentCardSources(bOnly.id);
        final arrived = (await repoA.getBlob(
          bSources.firstWhere((s) => s.blobId != null).blobId!,
        ))!;
        expect(
          utf8.decode(await a.session.readOriginal(arrived)),
          'fictional-b',
        );

        // The unresolved marker carries the foreign head; the documented
        // resolution adopts it and clears the marker.
        final conflicts = await a.merge.mergeConflicts();
        expect(conflicts[base.id]!.foreignHead, 4);
        expect(conflicts[base.id]!.kind, MergeConflictKind.fork);
        await repoA.restoreCardRevision(
          base.id,
          conflicts[base.id]!.foreignHead!,
        );
        await a.merge.clearMergeConflict(base.id);
        expect(await a.merge.mergeConflicts(), isEmpty);
        expect((await repoA.getCard(base.id))!.content, 'B 修改');

        // The answer travels back; B keeps its own projection and receives
        // A's card.
        final exportA2 = await a.backup.exportTransferToMedium(
          medium,
          _password,
          refreshUnlockedData: a.refresh,
        );
        final reportB = await b.merge.mergeFromMedium(
          medium,
          databaseName: exportA2.databaseName,
          credential: _password,
          clearUnlockedData: b.clearData,
          refreshUnlockedData: b.refresh,
        );
        expect(reportB.importedCards, 1);
        expect(reportB.fastForwardedCards, 1);
        expect(reportB.forkedCards, 1);
        expect(reportB.conflicts, hasLength(1));
        expect((await b.session.repository.getCard(base.id))!.content, 'B 修改');
        // 单向延伸：B 领到 A 的修改，无冲突。
        expect(
          (await b.session.repository.getCard(oneWay.id))!.content,
          'A 单向修改',
        );
        expect(await b.session.repository.getCard(aOnly.id), isNotNull);
        expect((await b.merge.mergeConflicts()).keys, [base.id]);
      } finally {
        await a.dispose();
        await b.dispose();
      }
    },
  );

  test('merge refuses a package from another vault lineage', () async {
    final root = await Directory.systemTemp.createTemp('relay-merge-');
    addTearDown(() => root.delete(recursive: true));
    final mediumDirectory = Directory('${root.path}/medium');
    await mediumDirectory.create(recursive: true);
    final medium = DirectoryTransferMedium(mediumDirectory);
    final a = Device(Directory('${root.path}/a'));
    final other = Device(Directory('${root.path}/other'));
    try {
      await a.createNewVault();
      await other.createNewVault();
      final export = await other.backup.exportTransferToMedium(
        medium,
        _password,
        refreshUnlockedData: other.refresh,
      );
      await expectLater(
        a.merge.mergeFromMedium(
          medium,
          databaseName: export.databaseName,
          credential: _password,
          clearUnlockedData: a.clearData,
          refreshUnlockedData: a.refresh,
        ),
        throwsA(
          isA<LifeVaultArchiveException>().having(
            (error) => error.message,
            'message',
            contains('另一套资料库'),
          ),
        ),
      );
      // The local vault is untouched and still writable.
      expect(a.session.state, VaultSessionState.unlocked);
      await a.session.repository.createCard(
        const CardDraft(title: '拒绝后仍可用', content: 'fixture'),
      );
      expect(
        (await a.session.repository.listCards()).any(
          (card) => card.title == '拒绝后仍可用',
        ),
        isTrue,
      );
    } finally {
      await a.dispose();
      await other.dispose();
    }
  });

  test('merge requires an unlocked vault', () async {
    final root = await Directory.systemTemp.createTemp('relay-merge-');
    addTearDown(() => root.delete(recursive: true));
    final mediumDirectory = Directory('${root.path}/medium');
    await mediumDirectory.create(recursive: true);
    final medium = DirectoryTransferMedium(mediumDirectory);
    final a = Device(Directory('${root.path}/a'));
    try {
      await a.createNewVault();
      await a.session.close();
      await expectLater(
        a.merge.mergeFromMedium(
          medium,
          databaseName: 'LiveRelay-deadbeef-database.lvault',
          credential: _password,
          clearUnlockedData: a.clearData,
          refreshUnlockedData: a.refresh,
        ),
        throwsStateError,
      );
    } finally {
      await a.dispose();
    }
  });
}
