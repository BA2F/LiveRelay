import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/ocr_provider.dart';

import '../support/session_fakes.dart';

import '../support/agent_service_headless_checks.dart';

void main() {
  test('disposing the real session invalidates a pending original and wipes both borrowed key and late bytes', () async {
    final repository = _OriginalRepository();
    final blobStore = _PendingBlob();
    final session = fixtureSession(
      openRepository: (_, _) async => repository,
      blobStore: blobStore,
    );
    try {
      await session.prepare();
      await session.openWithKey(
        Uint8List.fromList(List.generate(32, (i) => i + 1)),
      );
      session.markUnlocked();
      final content = VaultContentService(vault: session, ocr: _UnusedOcr());
      final rejected = expectLater(
        content.readOriginal('fixture-original'),
        throwsStateError,
      );
      final borrowedKey = await blobStore.entered.future;
      final generation = session.sessionGeneration;
      session.dispose();
      expect(session.sessionGeneration, greaterThan(generation));
      expect(session.isUnlocked, isFalse);
      expect(borrowedKey.every((byte) => byte == 0), isTrue);
      final clear = Uint8List.fromList([1, 2, 3]);
      blobStore.reply.complete(clear);
      await rejected;
      expect(clear.every((byte) => byte == 0), isTrue);
      expect(repository.closes, 1);
    } finally {
      if (!blobStore.reply.isCompleted) blobStore.reply.complete(Uint8List(0));
      session.dispose();
    }
  });
  for (final entry in agentServiceChecks().entries) {
    test(entry.key, entry.value);
  }
}

class _OriginalRepository extends SessionRepository {
  @override
  Future<VaultBlob?> getBlob(String id) async => VaultBlob(
    id: id,
    originalName: 'public.png',
    mediaKind: BlobMediaKind.image,
    mimeType: 'image/png',
    relativePath: 'fixture.blob',
    byteLength: 3,
    sha256: 'fixture',
    createdAt: DateTime.utc(2026),
  );
}

class _PendingBlob extends TrackingBlobStore {
  final entered = Completer<Uint8List>();
  final reply = Completer<Uint8List>();
  @override
  Future<Uint8List> read({
    required Directory vaultDirectory,
    required Uint8List masterKey,
    required VaultBlob blob,
  }) {
    entered.complete(masterKey);
    return reply.future;
  }
}

class _UnusedOcr implements OcrProvider {
  @override
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  }) => throw UnsupportedError('unused');
}
