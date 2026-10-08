import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import '../support/maintenance_headless_checks.dart';
import '../support/session_fakes.dart';

void main() {
  for (final entry in maintenanceChecks().entries) {
    test(entry.key, entry.value);
  }
  test('real session maintenance gate rejects competing operations and releases after error', () async {
    final session = fixtureSession();
    final entered = Completer<void>(), release = Completer<void>();
    final pending = session.exclusiveMaintenance(() async {
      entered.complete();
      await release.future;
      throw StateError('fixture failure');
    });
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    await expectLater(
      session.exclusiveMaintenance(() async => 1),
      throwsStateError,
    );
    release.complete();
    await rejected;
    expect(await session.exclusiveMaintenance(() async => 2), 2);
    session.dispose();
    await expectLater(
      session.exclusiveMaintenance(() async => 3),
      throwsStateError,
    );
  });
  test('disposing real session during repository open closes late handle and cannot resurrect key', () async {
    final entered = Completer<void>(), reply = Completer<SessionRepository>();
    final session = fixtureSession(
      openRepository: (_, _) {
        entered.complete();
        return reply.future;
      },
    );
    await session.prepare();
    final pending = session.openWithKey(Uint8List.fromList(List.filled(32, 4)));
    final rejected = expectLater(pending, throwsStateError);
    await entered.future;
    session.dispose();
    final repository = SessionRepository();
    reply.complete(repository);
    await rejected;
    expect(repository.closes, 1);
    expect(session.isUnlocked, isFalse);
    expect(() => session.repository, throwsStateError);
    await expectLater(session.openWithKey(Uint8List(32)), throwsStateError);
  });
}
