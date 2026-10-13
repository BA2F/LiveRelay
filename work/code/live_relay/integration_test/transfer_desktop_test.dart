import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/transfer/directory_transfer_medium.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:provider/provider.dart';

import '../test/support/verification_fakes.dart';

AppController makeController(Directory root) => createAppController(
  root,
  NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'whole-vault transfer between two roots through one medium directory',
    (tester) async {
      final root = await Directory.systemTemp.createTemp('relay-transfer-');
      final mediumDirectory = Directory('${root.path}/medium');
      final a = makeController(Directory('${root.path}/a'));
      final b = makeController(Directory('${root.path}/b'));
      addTearDown(() async {
        await a.lock().catchError((_) {});
        await b.lock().catchError((_) {});
        a.dispose();
        b.dispose();
        await root.delete(recursive: true);
      });
      final medium = DirectoryTransferMedium(mediumDirectory);
      await mediumDirectory.create(recursive: true);

      await a.initialize();
      final r1 = await a.generateRecovery();
      await a.setupModernVault(
        password: 'fictional-transfer-password',
        recoveryText: r1,
        recoveryConfirmation: r1,
      );
      await a.createCard(const CardDraft(title: '搬运卡片', content: 'fixture'));
      await a.importOriginal(
        bytes: Uint8List.fromList(utf8.encode('fictional-original')),
        originalName: 'fixture.txt',
        mimeType: 'text/plain',
        mediaKind: BlobMediaKind.document,
      );
      final export = await a.exportToMedium(medium, 'fictional-transfer-password');
      expect(export.writtenVolumes, hasLength(1));
      expect(
        (await mediumDirectory.list().toList()).whereType<File>(),
        hasLength(2),
        reason: 'one database package plus one originals volume',
      );

      await b.initialize();
      final report = await b.importFromMedium(
        medium,
        databaseName: export.databaseName,
        credential: 'fictional-transfer-password',
      );
      expect(report.requiresReset, isFalse);
      expect(report.remainingMissingOriginals, 0);
      expect(b.sessionState, VaultSessionState.unlocked);
      expect(b.cards.any((v) => v.title == '搬运卡片'), isTrue);
      final blob = b.blobs.single;
      expect(
        utf8.decode(await b.readOriginal(blob.id)),
        'fictional-original',
      );

      // The real desktop shell renders the imported vault without errors.
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: b,
          child: const LiveRelayApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('本地加密资料库'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      // The return trip ships only what the medium does not already carry.
      await b.importOriginal(
        bytes: Uint8List.fromList(utf8.encode('fictional-answer')),
        originalName: 'answer.txt',
        mimeType: 'text/plain',
        mediaKind: BlobMediaKind.document,
      );
      final back = await b.exportToMedium(medium, 'fictional-transfer-password');
      expect(back.skippedBlobs, 1);
      expect(back.writtenVolumes, hasLength(1));
      final answer = await a.importFromMedium(
        medium,
        databaseName: back.databaseName,
        credential: 'fictional-transfer-password',
      );
      expect(answer.harvestedOriginals, 1);
      expect(answer.volumesConsumed, 2);
      expect(answer.remainingMissingOriginals, 0);
      final answerBlob = a.blobs.singleWhere(
        (blob) => blob.originalName == 'answer.txt',
      );
      expect(
        utf8.decode(await a.readOriginal(answerBlob.id)),
        'fictional-answer',
      );
      expect(
        (await mediumDirectory.list().toList())
            .whereType<File>()
            .where((file) => file.path.contains('originals')),
        hasLength(2),
      );
    },
  );
}
