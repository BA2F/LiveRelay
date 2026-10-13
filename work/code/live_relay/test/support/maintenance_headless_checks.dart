// Executable with ordinary Dart; imports no Flutter, ZIP, SQLite or keyring.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_relay/application/vault_backup_service.dart';
import 'package:live_relay/application/vault_security_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/vault_archive.dart';
import 'package:live_relay/core/ports/vault_installation.dart';
import 'package:live_relay/core/ports/vault_maintenance.dart';
import 'package:live_relay/core/ports/vault_repository.dart';
import 'package:live_relay/core/security/recovery_credential.dart';
import 'package:live_relay/core/security/vault_archive_identity.dart';
import 'package:live_relay/core/security/vault_header_v3.dart';
import 'package:live_relay/core/security/vault_header_metadata.dart';

void check(bool value, String reason) {
  if (!value) throw StateError(reason);
}

bool wiped(Uint8List? bytes) => bytes != null && bytes.every((b) => b == 0);
Future<void> reject(Future<Object?> future, String message) async {
  Object? failure;
  try {
    await future;
  } on Object catch (e) {
    failure = e;
  }
  check(
    failure != null && '$failure'.contains(message),
    'Expected $message; got $failure',
  );
}

Map<String, Future<void> Function()> maintenanceChecks() => {
  'headless export uses injected ports and wipes proof after reopening':
      () async {
        final f = await Fixture.make();
        try {
          final bytes = await f.backup.export(
            'fixture-password',
            refreshUnlockedData: f.refresh,
          );
          check(
            bytes[0] == 8 &&
                f.vault.suspends == 1 &&
                f.vault.opens == 1 &&
                f.refreshes == 1,
            'Export/reopen did not use ports',
          );
          check(
            wiped(f.vault.proof) &&
                identical(f.archive.borrowedKey, f.vault.proof),
            'Proof not wiped',
          );
          check(!f.vault.maintenanceBusy, 'Gate leaked');
        } finally {
          await f.dispose();
        }
      },
  'locking during export discards late archive and never reopens': () async {
    final f = await Fixture.make();
    final output = Uint8List.fromList([8, 9]);
    f.archive.pending = Completer<Uint8List>();
    try {
      final rejected = reject(
        f.backup.export('fixture-password', refreshUnlockedData: f.refresh),
        '取消',
      );
      await f.archive.entered.future;
      await f.vault.close();
      f.archive.pending!.complete(output);
      await rejected;
      check(
        f.vault.opens == 0 && f.refreshes == 0 && !f.vault.isUnlocked,
        'Late export reopened',
      );
      check(
        wiped(output) && wiped(f.vault.proof),
        'Late export buffers not wiped',
      );
    } finally {
      await f.dispose();
    }
  },
  'locking during credential wait wipes proof without suspending or archiving':
      () async {
        final f = await Fixture.make();
        final proof = Uint8List.fromList(List.filled(32, 3));
        f.vault.pendingProof = Completer<Uint8List>();
        try {
          final rejected = reject(
            f.backup.export('fixture-password', refreshUnlockedData: f.refresh),
            '取消',
          );
          await f.vault.authenticationEntered.future;
          await f.vault.close();
          f.vault.pendingProof!.complete(proof);
          await rejected;
          check(
            wiped(proof) &&
                f.vault.suspends == 0 &&
                f.archive.kinds.isEmpty &&
                f.vault.opens == 0,
            'Cancelled auth proceeded',
          );
        } finally {
          await f.dispose();
        }
      },
  'split second-package failure wipes first output and reopens unchanged vault':
      () async {
        final f = await Fixture.make();
        f.archive.failAttachments = true;
        try {
          await reject(
            f.backup.exportSplit('fixture-password', f.refresh),
            'fixture archive failure',
          );
          check(
            wiped(f.archive.firstOutput) && wiped(f.vault.proof),
            'Split buffers leaked',
          );
          check(
            f.vault.opens == 1 && f.refreshes == 1 && f.vault.isUnlocked,
            'Split failure did not reopen',
          );
          final expected = await stableArchiveSnapshotId(
            vaultId: f.vault.identity!.vaultId,
            epoch: f.vault.identity!.epoch,
          );
          check(
            f.archive.snapshots.length == 2 &&
                f.archive.snapshots[0] == expected &&
                f.archive.snapshots[1] == expected,
            'Pairing ID changed',
          );
        } finally {
          await f.dispose();
        }
      },
  'preview uses staged metadata without ZIP decoding and keeps borrowed input':
      () async {
        final f = await Fixture.make();
        final bytes = Uint8List.fromList([99, 88]); // deliberately not ZIP
        try {
          final preview = await f.backup.inspect(bytes, 'fixture-password');
          check(
            preview.createdAt == DateTime.utc(2026, 10, 8) &&
                preview.requiresReset,
            'Metadata lost',
          );
          check(
            preview.cards == 0 &&
                f.repository.closes == 1 &&
                wiped(f.vault.proof),
            'Preview cleanup failed',
          );
          check(
            !await f.archive.staged!.directory.exists() && bytes.first == 99,
            'Preview ownership changed',
          );
          check(
            f.vault.opens == 0 && f.vault.closes == 0,
            'Preview touched live vault',
          );
        } finally {
          await f.dispose();
        }
      },
  'restore v3 verifies before commit and exposes only restricted recovery':
      () async {
        final f = await Fixture.make();
        final bytes = Uint8List.fromList([99, 88]);
        try {
          await f.backup.restore(
            bytes,
            'fixture-password',
            clearUnlockedData: () => f.clears++,
            refreshUnlockedData: f.refresh,
          );
          check(
            f.transaction.verified &&
                f.transaction.committed &&
                f.vault.state == VaultSessionState.recovering,
            'Restore bypassed restricted gate',
          );
          check(
            f.vault.opens == 1 &&
                f.clears == 1 &&
                f.refreshes == 0 &&
                f.vault.legacyDisables == 0,
            'Restore changed legacy or UI contract',
          );
          check(
            wiped(bytes) && wiped(f.vault.proof) && !f.vault.maintenanceBusy,
            'Restore cleanup failed',
          );
        } finally {
          await f.dispose();
        }
      },
  'failed archive authentication cannot replace active vault and clears consumed input':
      () async {
        final f = await Fixture.make();
        f.archive.failAuthentication = true;
        final bytes = Uint8List.fromList([99, 88]);
        try {
          await reject(
            f.backup.restore(
              bytes,
              'fixture-password',
              clearUnlockedData: () => f.clears++,
              refreshUnlockedData: f.refresh,
            ),
            'fixture MAC failure',
          );
          check(
            f.vault.closes == 0 &&
                f.transaction.installs == 0 &&
                f.vault.isUnlocked,
            'Unauthenticated replacement touched active vault',
          );
          check(
            wiped(bytes) &&
                wiped(f.vault.proof) &&
                !await f.archive.staged!.directory.exists(),
            'Authentication failure leaked staging or key',
          );
        } finally {
          await f.dispose();
        }
      },
  'backup and security share maintenance gate, including consumed-input rejection':
      () async {
        final f = await Fixture.make();
        final security = VaultSecurityService(f.vault, () => f.transaction);
        f.archive.pending = Completer<Uint8List>();
        try {
          final export = f.backup.export(
            'fixture-password',
            refreshUnlockedData: f.refresh,
          );
          await f.archive.entered.future;
          await reject(
            security.configure(
              oldPassword: '',
              newPassword: '',
              recoveryText: '',
              recoveryConfirmation: '',
            ),
            '维护正在进行',
          );
          final bytes = Uint8List.fromList([6, 7]);
          await reject(f.backup.importSupplement(bytes), '维护正在进行');
          check(wiped(bytes), 'Gate rejection did not wipe consumed input');
          f.archive.pending!.complete(Uint8List.fromList([8]));
          await export;
          final rejectedInput = Uint8List.fromList([4]);
          f.vault.currentState = VaultSessionState.locked;
          await reject(f.backup.importSupplement(rejectedInput), '请先解锁');
          check(
            wiped(rejectedInput) && !f.vault.maintenanceBusy,
            'Early rejection leaked input/gate',
          );
        } finally {
          security.dispose();
          await f.dispose();
        }
      },
  'headless security rotation emits pure progress and wipes all borrowed material':
      () async {
        final f = await Fixture.make();
        final security = VaultSecurityService(f.vault, () => f.transaction);
        final progress = <VaultSecurityProgress>[];
        final finished = Completer<void>();
        final subscription = security.changes.listen((event) {
          progress.add(event);
          if (!event.busy && !finished.isCompleted) finished.complete();
        });
        final recovery = RecoveryCredential.generate();
        try {
          final text = await recovery.encode();
          await security.configure(
            oldPassword: 'fixture-password',
            newPassword: 'new-fixture-password',
            recoveryText: text,
            recoveryConfirmation: text,
          );
          await finished.future;
          check(
            f.transaction.verified &&
                f.transaction.committed &&
                f.vault.isUnlocked,
            'Rotation did not verify/commit',
          );
          check(
            progress.any((e) => e.stage == '核验并提交新资料库') &&
                progress.last.stage.isEmpty,
            'Progress lifecycle lost',
          );
          check(
            f.vault.writtenHeader?.generation == 1 && f.repository.imports == 1,
            'State/header not transferred',
          );
          check(
            wiped(f.vault.proof) &&
                wiped(f.vault.borrowedOldKey) &&
                wiped(f.vault.borrowedNextKey) &&
                wiped(f.repository.snapshot),
            'Rotation material leaked',
          );
          check(
            !security.busy && !f.vault.maintenanceBusy,
            'Rotation gates leaked',
          );
        } finally {
          recovery.dispose();
          await subscription.cancel();
          security.dispose();
          await f.dispose();
        }
      },
};

class Fixture {
  Fixture(
    this.root,
    this.vault,
    this.archive,
    this.repository,
    this.transaction,
  ) {
    backup = VaultBackupService(
      session: vault,
      archive: archive,
      restoreTransaction: () => transaction,
    );
  }
  final Directory root;
  final FakeVault vault;
  final FakeArchive archive;
  final FakeRepository repository;
  final FakeInstallation transaction;
  late final VaultBackupService backup;
  int refreshes = 0, clears = 0;
  Future<void> refresh() async {
    refreshes++;
  }

  static Future<Fixture> make() async {
    final root = await Directory.systemTemp.createTemp(
      'relay-maintenance-check-',
    );
    final repo = FakeRepository();
    final vault = FakeVault(Directory('${root.path}/vault'), repo);
    return Fixture(root, vault, FakeArchive(), repo, FakeInstallation());
  }

  Future<void> dispose() => root.delete(recursive: true);
}

class FakeVault implements VaultMaintenance {
  FakeVault(this.directory, this.repository);
  @override
  final Directory directory;
  @override
  final FakeRepository repository;
  VaultSessionState currentState = VaultSessionState.unlocked;
  @override
  VaultSessionState get state => currentState;
  @override
  bool get isUnlocked => state == VaultSessionState.unlocked;
  @override
  int operationEpoch = 0;
  @override
  int sessionGeneration = 0;
  @override
  VaultHeaderMetadata? get header => VaultHeaderMetadata(
    passwordKind: 'custom',
    wordCount: null,
    biometricEnabled: false,
    createdAt: DateTime.utc(2026),
    formatVersion: 3,
  );
  @override
  get deviceProtection => null;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  bool get isMaintaining => maintenanceBusy;
  @override
  bool get isWriting => false;
  @override
  Future<T> runMutation<T>(Future<T> Function() operation) => operation();
  bool maintenanceBusy = false;
  int suspends = 0, opens = 0, closes = 0, legacyDisables = 0;
  Uint8List? proof, borrowedOldKey, borrowedNextKey;
  VaultHeaderV3? writtenHeader;
  Completer<Uint8List>? pendingProof;
  final authenticationEntered = Completer<void>();
  @override
  Future<T> exclusiveMaintenance<T>(Future<T> Function() operation) async {
    if (maintenanceBusy) throw StateError('资料库维护正在进行');
    maintenanceBusy = true;
    try {
      return await operation();
    } finally {
      maintenanceBusy = false;
    }
  }

  @override
  Future<Uint8List> authenticateDaily(
    String password, {
    Uint8List? keyFile,
  }) async {
    if (!authenticationEntered.isCompleted) authenticationEntered.complete();
    proof = pendingProof == null
        ? Uint8List.fromList(List.filled(32, 3))
        : await pendingProof!.future;
    return proof!;
  }

  @override
  Future<Uint8List> authenticateRecovery(String text) =>
      authenticateDaily(text);
  @override
  Future<Uint8List> authenticateStaged(
    Directory staged,
    String credential,
    VaultHeaderMetadata metadata,
  ) => authenticateDaily(credential);
  @override
  Future<void> suspendDatabase() async {
    suspends++;
    sessionGeneration++;
  }

  @override
  Future<void> openWithKey(Uint8List key) async {
    opens++;
    sessionGeneration++;
  }

  @override
  Future<void> close() async {
    closes++;
    operationEpoch++;
    currentState = VaultSessionState.locked;
  }

  @override
  Future<VaultHeaderMetadata?> readStagedHeader(Directory staged) async =>
      header;
  @override
  Future<VaultRepository> openTemporary(
    Directory directory,
    Uint8List key,
  ) async {
    borrowedNextKey = key;
    return repository;
  }

  @override
  Future<void> disableStagedLegacyBiometric(Directory staged) async {
    legacyDisables++;
  }

  @override
  Future<void> reloadHeader() async {}
  @override
  Future<void> inspectRecoveredHeader() async {
    currentState = VaultSessionState.locked;
  }

  @override
  Future<void> clearDeviceKeyAfterRestore() async {}
  @override
  void markUnlocked() {
    currentState = VaultSessionState.unlocked;
  }

  @override
  void markRecovering() {
    currentState = VaultSessionState.recovering;
  }

  @override
  void fail() {
    currentState = VaultSessionState.failure;
  }

  @override
  Future<T> withMasterKey<T>(
    Future<T> Function(Uint8List key) operation,
  ) async {
    final key = borrowedOldKey = Uint8List.fromList(List.filled(32, 3));
    try {
      return await operation(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
  }

  @override
  Future<VaultHeaderV3?> modernHeader() async => null;
  ({String vaultId, int epoch})? identity = (
    vaultId: '11111111111111111111111111111111',
    epoch: 1,
  );
  @override
  Future<({String vaultId, int epoch})?> archiveIdentity() async => identity;
  @override
  Future<void> writeStagedHeader(
    Directory directory,
    VaultHeaderV3 header,
  ) async {
    writtenHeader = header;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeRepository implements VaultRepository {
  int closes = 0, imports = 0;
  Uint8List? snapshot;
  @override
  Future<String?> readLocalValue(String name) async => null;
  @override
  Future<Uint8List> exportLocalState() async =>
      snapshot = Uint8List.fromList([10]);
  @override
  Future<void> importLocalState(Uint8List bytes) async {
    check(bytes.first == 10, 'Snapshot already wiped');
    imports++;
  }

  @override
  Future<List<VaultBlob>> listBlobs() async => [];
  @override
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
    bool recycled = false,
  }) async => [];
  @override
  Future<List<CredentialEntry>> listCredentials({
    String query = '',
    bool recycled = false,
  }) async => [];
  @override
  Future<void> close() async {
    closes++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeArchive implements VaultArchive {
  Completer<Uint8List>? pending;
  final entered = Completer<void>();
  final kinds = <String>[], snapshots = <String?>[], blobSubsets = <Set<String>?>[];
  Uint8List? borrowedKey, firstOutput;
  StagedLifeVault? staged;
  ArchiveContainerSummary? containerSummary;
  bool failAttachments = false, failAuthentication = false;
  @override
  Future<Uint8List> create({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    DateTime? createdAt,
    String kind = 'full',
    String? snapshotId,
    Set<String>? blobPaths,
  }) async {
    borrowedKey = masterKey;
    kinds.add(kind);
    snapshots.add(snapshotId);
    blobSubsets.add(blobPaths);
    if (!entered.isCompleted) entered.complete();
    if (failAttachments && kind == 'attachments') {
      throw StateError('fixture archive failure');
    }
    return pending == null
        ? firstOutput = Uint8List.fromList([8])
        : await pending!.future;
  }

  @override
  ArchiveContainerSummary? inspectContainerPrefix(Uint8List prefix) =>
      containerSummary;

  @override
  Future<StagedLifeVault> stage({
    required Uint8List archiveBytes,
    required Directory stagingParent,
  }) async => staged = StagedLifeVault(
    directory: await stagingParent.createTemp('liverelay-restore-'),
    manifestBytes: Uint8List(0),
    manifestMac: Uint8List(0),
    version: 2,
    createdAt: DateTime.utc(2026, 10, 8),
  );
  @override
  Future<void> verifyAuthentication({
    required StagedLifeVault staged,
    required Uint8List masterKey,
  }) async {
    if (failAuthentication) throw StateError('fixture MAC failure');
  }
}

class FakeInstallation implements VaultInstallation {
  bool verified = false, committed = false;
  int installs = 0, recovers = 0;
  @override
  Future<String?> recover() async {
    recovers++;
    return null;
  }

  @override
  Future<String?> install(
    Directory staged, {
    required Future<void> Function() verifyInstalled,
    required Future<void> Function() closeInstalled,
  }) async {
    installs++;
    try {
      await verifyInstalled();
      verified = true;
      committed = true;
      return null;
    } on Object {
      await closeInstalled();
      await recover();
      rethrow;
    }
  }
}

Future<void> main() async {
  for (final entry in maintenanceChecks().entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
