import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:provider/provider.dart';

import '../test/support/verification_fakes.dart';

AppController makeController(Directory directory) => createAppController(
  directory,
  NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'real encrypted vault survives subprocess exit between directory renames',
    (tester) async {
      const project = String.fromEnvironment('RESTORE_TEST_PROJECT');
      expect(
        project,
        isNotEmpty,
        reason: 'Pass the workspace path as RESTORE_TEST_PROJECT',
      );
      final directory = await Directory.systemTemp.createTemp(
        'relay-native-recovery-',
      );
      final source = makeController(Directory('${directory.path}/source'));
      final targetRoot = Directory('${directory.path}/target');
      final target = makeController(targetRoot);
      AppController? restarted;
      Uint8List? backup;
      const oldPassword = 'native-old-password-2026';
      const newPassword = 'native-new-password-2026';
      try {
        await source.initialize();
        await source.setupVault(
          password: newPassword,
          usesChinesePassphrase: false,
        );
        await source.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('new-original-fixture')),
          originalName: 'new.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );
        backup = await source.exportVault(newPassword);
        await source.lock();
        await target.initialize();
        await target.setupVault(
          password: oldPassword,
          usesChinesePassphrase: false,
        );
        await target.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('old-original-fixture')),
          originalName: 'old.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );
        await target.lock();
        final vault = Directory('${targetRoot.path}/live_relay/vault');
        final archive = LifeVaultArchiveService();
        final staged = await archive.stage(
          archiveBytes: backup,
          stagingParent: vault.parent,
        );
        final manager = VaultKeyManager(staged.directory);
        final key = await manager.unlock(newPassword);
        await archive.verifyAuthentication(staged: staged, masterKey: key);
        await manager.setBiometricEnabled(false);
        final stagedDatabase = await AppDatabase.openEncrypted(
          vaultDirectory: staged.directory,
          masterKey: key,
        );
        await stagedDatabase.close();
        key.fillRange(0, key.length, 0);
        final child = await Process.run('dart', [
          'run',
          'test/support/restore_crash_worker.dart',
          vault.path,
          staged.directory.path,
          'originalMoved',
        ], workingDirectory: project);
        expect(child.exitCode, 87, reason: '${child.stdout}\n${child.stderr}');
        expect(await vault.exists(), isFalse);

        restarted = makeController(targetRoot);
        await restarted.initialize();
        expect(restarted.sessionState, VaultSessionState.locked);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: restarted,
            child: const LiveRelayApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('原资料库已找回'), findsOneWidget);
        expect(find.text('欢迎使用留灯'), findsNothing);
        await restarted.unlockWithPassword(oldPassword);
        expect(
          utf8.decode(await restarted.readOriginal(restarted.blobs.single.id)),
          'old-original-fixture',
        );
        await restarted.lock();
        await expectLater(
          restarted.unlockWithPassword(newPassword),
          throwsA(anything),
        );
        await restarted.unlockWithPassword(oldPassword);
        await restarted.restoreVault(Uint8List.fromList(backup), newPassword);
        expect(
          utf8.decode(await restarted.readOriginal(restarted.blobs.single.id)),
          'new-original-fixture',
        );
        await restarted.lock();
        await expectLater(
          restarted.unlockWithPassword(oldPassword),
          throwsA(anything),
        );
        await restarted.unlockWithPassword(newPassword);
        final exported = await restarted.exportVault(newPassword);
        final preview = await restarted.inspectBackup(exported, newPassword);
        expect(preview.originals, 1);
        exported.fillRange(0, exported.length, 0);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        if (restarted?.isUnlocked ?? false) await restarted!.lock();
        restarted?.dispose();
        if (source.isUnlocked) await source.lock();
        source.dispose();
        if (target.isUnlocked) await target.lock();
        target.dispose();
        backup?.fillRange(0, backup.length, 0);
        await directory.delete(recursive: true);
      }
    },
  );
}
