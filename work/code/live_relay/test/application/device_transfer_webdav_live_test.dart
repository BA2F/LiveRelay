import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/transfer/webdav_transfer_medium.dart';

import '../support/verification_fakes.dart';

/// Whole-vault device transfer over a real WebDAV server (the deployed
/// copyparty service). Opt-in so the ordinary suite stays self-contained:
///   flutter test test/application/device_transfer_webdav_live_test.dart \
///     --dart-define=COPYPARTY_URL=http://127.0.0.1:3923/alice/ \
///     --dart-define=COPYPARTY_USER=alice \
///     --dart-define=COPYPARTY_PASS=alicepass
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The test binding replaces the global HttpClient with one that answers
  // every request with HTTP 400; the live round trip needs the real one.
  HttpOverrides.global = null;
  const url = String.fromEnvironment('COPYPARTY_URL');
  const user = String.fromEnvironment('COPYPARTY_USER');
  const pass = String.fromEnvironment('COPYPARTY_PASS');

  test(
    'whole-vault transfer round trips through a live WebDAV medium',
    skip: url.isEmpty ? '需要 COPYPARTY_URL 等 dart-define' : null,
    () async {
      final root = await Directory.systemTemp.createTemp('relay-cloud-');
      addTearDown(() => root.delete(recursive: true));
      WebDavTransferMedium medium() => WebDavTransferMedium(
        baseUrl: Uri.parse(url),
        username: user,
        password: pass,
      );
      AppController controller(Directory root) => createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final a = controller(Directory('${root.path}/a'));
      final b = controller(Directory('${root.path}/b'));
      try {
        await a.initialize();
        final r1 = await a.generateRecovery();
        await a.setupModernVault(
          password: 'fictional-cloud-password',
          recoveryText: r1,
          recoveryConfirmation: r1,
        );
        await a.createCard(const CardDraft(title: '云端卡片', content: 'fixture'));
        await a.importOriginal(
          bytes: Uint8List.fromList(utf8.encode('fictional-cloud-original')),
          originalName: 'cloud.txt',
          mimeType: 'text/plain',
          mediaKind: BlobMediaKind.other,
        );

        final first = await a.exportToMedium(medium(), 'fictional-cloud-password');
        expect(first.writtenVolumes, hasLength(1));

        await b.initialize();
        final report = await b.importFromMedium(
          medium(),
          databaseName: first.databaseName,
          credential: 'fictional-cloud-password',
        );
        expect(report.requiresReset, isFalse);
        expect(report.remainingMissingOriginals, 0);
        expect(b.sessionState, VaultSessionState.unlocked);
        expect(b.cards.any((v) => v.title == '云端卡片'), isTrue);
        final blob = b.blobs.singleWhere((blob) => blob.originalName == 'cloud.txt');
        expect(
          utf8.decode(await b.readOriginal(blob.id)),
          'fictional-cloud-original',
        );

        // Second export through the same medium: coverage now lives in the
        // vault's transfer index, so nothing re-uploads.
        final again = await a.exportToMedium(medium(), 'fictional-cloud-password');
        expect(again.writtenVolumes, isEmpty);
        expect(again.skippedBlobs, 1);
      } finally {
        await a.lock().catchError((_) {});
        await b.lock().catchError((_) {});
        a.dispose();
        b.dispose();
      }
    },
  );
}
