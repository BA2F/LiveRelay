import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/biometric_key_store.dart';

import '../support/verification_fakes.dart';

class StoredBiometrics implements BiometricKeyStore {
  Uint8List? key;
  int reads = 0;
  bool failClear = false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Future<void> saveMasterKey(Uint8List masterKey) async {
    key = Uint8List.fromList(masterKey);
  }

  @override
  Future<Uint8List?> readMasterKey() async {
    reads++;
    return key == null ? null : Uint8List.fromList(key!);
  }

  @override
  Future<void> clear() async {
    if (failClear) throw const FileSystemException('device clear denied');
    key?.fillRange(0, key!.length, 0);
    key = null;
  }
}

AppController controller(
  Directory root, {
  BiometricKeyStore? biometrics,
  Future<void> Function(String)? checkpoint,
}) => createAppController(
  root,
  biometrics ?? NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
  checkpoint,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'password OR biometrics remain independent daily unlock paths',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-or-');
      addTearDown(() => root.delete(recursive: true));
      final store = StoredBiometrics();
      final c = controller(root, biometrics: store);
      await c.initialize();
      await c.setupVault(
        password: 'independent-password',
        usesChinesePassphrase: false,
        enableBiometric: true,
      );
      await c.createCard(
        const CardDraft(title: 'OR marker', content: 'fixture'),
      );
      await c.lock();
      await c.unlockWithBiometric();
      expect(c.cards.single.title, 'OR marker');
      expect(store.reads, 1);
      await c.lock();
      await c.unlockWithPassword('independent-password');
      expect(c.cards.single.title, 'OR marker');
      expect(store.reads, 1);
      await c.setBiometricEnabled(false);
      await c.lock();
      await expectLater(c.unlockWithBiometric(), throwsStateError);
      expect(store.reads, 1);
      await c.unlockWithPassword('independent-password');
      await c.lock();
      c.dispose();
    },
  );

  test('restore uses new password and originals, excludes sidecars, rejects stale device key after failed clear and restart', () async {
    final root = await Directory.systemTemp.createTemp(
      'relay-restore-controller-',
    );
    addTearDown(() => root.delete(recursive: true));
    final sourceRoot = Directory('${root.path}/source');
    final targetRoot = Directory('${root.path}/target');
    final source = controller(sourceRoot);
    await source.initialize();
    await source.setupVault(
      password: 'new-backup-password',
      usesChinesePassphrase: false,
    );
    await source.importOriginal(
      bytes: Uint8List.fromList(utf8.encode('fixture-original')),
      originalName: 'fixture.txt',
      mimeType: 'text/plain',
      mediaKind: BlobMediaKind.other,
    );
    // Produces predecessor sidecar; it must be absent from the public backup.
    await source.setBiometricEnabled(false);
    final archive = await source.exportVault('new-backup-password');
    final entries = ZipDecoder()
        .decodeBytes(archive)
        .files
        .map((file) => file.name)
        .toList();
    expect(
      entries.any(
        (name) => name.endsWith('.tmp') || name.contains('.restore.'),
      ),
      isFalse,
    );
    final store = StoredBiometrics();
    final target = controller(targetRoot, biometrics: store);
    await target.initialize();
    await target.setupVault(
      password: 'old-target-password',
      usesChinesePassphrase: false,
      enableBiometric: true,
    );
    await target.createCard(
      const CardDraft(title: 'old content', content: 'old'),
    );
    store.failClear = true;
    await target.restoreVault(archive, 'new-backup-password');
    expect(target.header!.biometricEnabled, isFalse);
    expect(
      utf8.decode(await target.readOriginal(target.blobs.single.id)),
      'fixture-original',
    );
    await target.lock();
    await expectLater(target.unlockWithBiometric(), throwsStateError);
    expect(store.reads, 0);
    await expectLater(
      target.unlockWithPassword('old-target-password'),
      throwsA(anything),
    );
    await target.unlockWithPassword('new-backup-password');
    await target.lock();
    target.dispose();
    final restarted = controller(targetRoot, biometrics: store);
    await restarted.initialize();
    expect(restarted.sessionState, VaultSessionState.locked);
    await expectLater(restarted.unlockWithBiometric(), throwsStateError);
    expect(store.reads, 0);
    await restarted.unlockWithPassword('new-backup-password');
    expect(restarted.blobs, hasLength(1));
    await restarted.lock();
    restarted.dispose();
    await source.lock();
    source.dispose();
  });

  test('failed install restores old encrypted data and new controller cannot create over it', () async {
    final root = await Directory.systemTemp.createTemp(
      'relay-restore-failure-',
    );
    addTearDown(() => root.delete(recursive: true));
    final source = controller(Directory('${root.path}/source'));
    await source.initialize();
    await source.setupVault(
      password: 'new-source-password',
      usesChinesePassphrase: false,
    );
    await source.createCard(const CardDraft(title: 'new', content: 'new'));
    final archive = await source.exportVault('new-source-password');
    final targetRoot = Directory('${root.path}/target');
    final target = controller(
      targetRoot,
      checkpoint: (stage) async {
        if (stage == 'incomingInstalled') {
          throw const FileSystemException('injected');
        }
      },
    );
    await target.initialize();
    await target.setupVault(
      password: 'old-source-password',
      usesChinesePassphrase: false,
    );
    await target.createCard(const CardDraft(title: 'old', content: 'old'));
    await expectLater(
      target.restoreVault(archive, 'new-source-password'),
      throwsA(anything),
    );
    expect(target.sessionState, VaultSessionState.locked);
    target.dispose();
    final restarted = controller(targetRoot);
    await restarted.initialize();
    expect(restarted.sessionState, VaultSessionState.locked);
    await expectLater(
      restarted.setupVault(
        password: 'replacement-password',
        usesChinesePassphrase: false,
      ),
      throwsStateError,
    );
    await restarted.unlockWithPassword('old-source-password');
    expect(restarted.cards.single.title, 'old');
    await restarted.lock();
    restarted.dispose();
    await source.lock();
    source.dispose();
  });

  test(
    'orphan rollback and partial header are failures rather than empty setup',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-orphan-');
      addTearDown(() => root.delete(recursive: true));
      await Directory('${root.path}/live_relay/vault.rollback-orphan')
          .create(recursive: true);
      final c = controller(root);
      await c.initialize();
      expect(c.sessionState, VaultSessionState.failure);
      await c.lock();
      expect(c.sessionState, VaultSessionState.failure);
      await expectLater(
        c.unlockWithPassword('must-not-unlock'),
        throwsA(anything),
      );
      await expectLater(c.unlockWithBiometric(), throwsA(anything));
      await expectLater(
        c.setupVault(password: 'must-not-create', usesChinesePassphrase: false),
        throwsStateError,
      );
      expect(
        await Directory('${root.path}/live_relay/vault').exists(),
        isFalse,
      );
      c.dispose();
    },
  );
}
