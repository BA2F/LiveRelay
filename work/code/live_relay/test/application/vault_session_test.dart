import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/core/domain/entities.dart';

import '../support/session_fakes.dart';

final blob = VaultBlob(
  id: 'fixture',
  originalName: 'fixture.txt',
  mediaKind: BlobMediaKind.document,
  mimeType: 'text/plain',
  relativePath: 'blobs/fixture.blob',
  byteLength: 3,
  sha256: 'fixture-only',
  createdAt: DateTime.utc(2026),
);

void main() {
  test(
    'session copies caller key, closes replaced repository and wipes old key',
    () async {
      final files = TrackingBlobStore();
      final repositories = <SessionRepository>[];
      final session = fixtureSession(
        blobStore: files,
        openRepository: (_, _) async {
          final repository = SessionRepository();
          repositories.add(repository);
          return repository;
        },
      );
      await session.prepare();
      final first = Uint8List.fromList(List.filled(32, 7));
      await session.openWithKey(first);
      first.fillRange(0, first.length, 0);
      await session.readOriginal(blob);
      final retained = files.borrowedKey!;
      expect(retained, everyElement(7));
      await session.openWithKey(Uint8List.fromList(List.filled(32, 9)));
      expect(repositories.first.closes, 1);
      expect(retained, everyElement(0));
      await session.close();
      expect(repositories.last.closes, 1);
      expect(() => session.repository, throwsStateError);
      expect(() => session.readOriginal(blob), throwsStateError);
    },
  );

  test('close failure still wipes key and detaches repository', () async {
    final repository = SessionRepository()..failClose = true;
    final files = TrackingBlobStore();
    final session = fixtureSession(
      blobStore: files,
      openRepository: (_, _) async => repository,
    );
    await session.prepare();
    await session.openWithKey(Uint8List.fromList(List.filled(32, 3)));
    session.markUnlocked();
    await session.readOriginal(blob);
    final retained = files.borrowedKey!;
    await expectLater(session.close(), throwsStateError);
    expect(retained, everyElement(0));
    expect(session.state, VaultSessionState.locked);
    expect(() => session.repository, throwsStateError);
    await session.close();
    expect(repository.closes, 1);
  });

  test(
    'dispose wipes key immediately and failure state survives close',
    () async {
      final repository = SessionRepository();
      final files = TrackingBlobStore();
      final session = fixtureSession(
        blobStore: files,
        openRepository: (_, _) async => repository,
      );
      await session.prepare();
      await session.openWithKey(Uint8List.fromList(List.filled(32, 5)));
      await session.readOriginal(blob);
      final retained = files.borrowedKey!;
      session.fail();
      await session.close();
      expect(session.state, VaultSessionState.failure);
      expect(retained, everyElement(0));
      await session.openWithKey(Uint8List.fromList(List.filled(32, 6)));
      await session.readOriginal(blob);
      final nextKey = files.borrowedKey!;
      session.dispose();
      expect(nextKey, everyElement(0));
      expect(() => session.repository, throwsStateError);
      expect(repository.closes, 2);
    },
  );
}
