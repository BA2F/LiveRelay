import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:live_relay/core/identity/hpke.dart';
import 'package:live_relay/core/security/header_encoding.dart';
import 'package:live_relay/application/local_handoff_service.dart';
import 'package:live_relay/application/recipient_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/identity/local_identity.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../support/session_fakes.dart';

void main() {
  test('real scoped delivery proves both keys, excludes unselected secrets, rejects replay and survives identity restore', () async {
    final root = await Directory.systemTemp.createTemp('handoff-unit-');
    final repository = SqliteVaultRepository(AppDatabase.inMemory());
    final session = fixtureSession(
      directory: Directory('${root.path}/owner'),
      openRepository: (_, _) async => repository,
    );
    final receiver = RecipientService(
      () async => Directory('${root.path}/recipient'),
    );
    final restored = RecipientService(
      () async => Directory('${root.path}/recipient-restored'),
    );
    try {
      await session.prepare();
      await session.openWithKey(Uint8List(32));
      session.markUnlocked();
      final owner = LocalHandoffService(session);
      await owner.saveProfile('虚构所有者', 'fictional', 'private profile');
      await receiver.initialize();
      await receiver.create('虚构接收者', 'recipient-password');
      final public = await receiver.identity!.publicData(),
          recipientFp = await receiver.identity!.fingerprint();
      await expectLater(
        owner.createChallenge(public, 'unverified'),
        throwsFormatException,
      );
      final challenge = jsonDecode(
        utf8.decode(await owner.createChallenge(public, recipientFp)),
      ) as Map<String, Object?>;
      final ownerFp = await LocalIdentity.fingerprintOf(
        await owner.publicIdentity(),
      );
      final proof = jsonDecode(
        utf8.decode(await receiver.answerChallenge(challenge, ownerFp)),
      ) as Map<String, Object?>;
      await owner.acceptProof(proof);
      await expectLater(owner.acceptProof(proof), throwsStateError);
      final card = await repository.createCard(
        const CardDraft(title: '可交付标题', content: 'private-body-not-authorized'),
      );
      final credential = await repository.saveCredential(
        const CredentialDraft(
          title: '虚构密码',
          username: 'fictional',
          secret: 'unselected-secret',
          notes: 'unselected-note',
        ),
      );
      await repository.saveCredential(
        const CredentialDraft(
          title: '虚构密码',
          username: 'fictional',
          secret: 'current-secret',
        ),
        id: credential.id,
      );
      final wire = await owner.exportScope(recipientFp, [
        ScopedRecord('card', card.id, VisibilityLevel.existence),
        ScopedRecord('credential', credential.id, VisibilityLevel.summary),
      ]);
      expect(utf8.decode(wire), isNot(contains('current-secret')));
      final wrongIdentity = await LocalIdentity.create('无权接收者');
      final envelope = jsonDecode(utf8.decode(wire)) as Map<String, Object?>;
      final aad = Map<String, Object?>.from(envelope)
        ..remove('box')
        ..remove('signature');
      try {
        await expectLater(
          LocalHpke.open(
            Map<String, Object?>.from(envelope['box'] as Map),
            wrongIdentity.dh,
            HeaderEncoding.encode(aad),
          ),
          throwsA(isA<SecretBoxAuthenticationError>()),
        );
      } finally {
        wrongIdentity.dispose();
      }
      await receiver.receive(wire, ownerFp);
      final payload = jsonEncode(receiver.snapshot);
      for (final excluded in [
        'private-body-not-authorized',
        'unselected-secret',
        'current-secret',
        'unselected-note',
        'private profile',
      ]) {
        expect(payload, isNot(contains(excluded)));
      }
      await expectLater(receiver.receive(wire, ownerFp), throwsStateError);
      final backup = await receiver.exportProtectedIdentity();
      await restored.initialize();
      await restored.importProtectedIdentity(backup, 'recipient-password');
      expect(await restored.identity!.fingerprint(), recipientFp);
      await expectLater(restored.receive(wire, ownerFp), throwsStateError);
      final next = await owner.exportScope(recipientFp, [
        ScopedRecord(
          'credential',
          credential.id,
          VisibilityLevel.secret,
          history: true,
        ),
      ]);
      await restored.receive(next, ownerFp);
      expect(jsonEncode(restored.snapshot), contains('current-secret'));
      expect(jsonEncode(restored.snapshot), contains('unselected-secret'));
      final saved = (await restored.savedPackages()).single;
      restored.lock();
      await restored.unlock('recipient-password');
      await restored.receive(await saved.readAsBytes(), ownerFp, saved: true);
      expect(jsonEncode(restored.snapshot), contains('current-secret'));
    } finally {
      receiver.dispose();
      restored.dispose();
      await session.close();
      session.dispose();
      await root.delete(recursive: true);
    }
  });
  test(
    'database state roundtrip preserves history; invalid import rolls back',
    () async {
      final a = SqliteVaultRepository(AppDatabase.inMemory()),
          b = SqliteVaultRepository(AppDatabase.inMemory());
      try {
        final card = await a.createCard(
          const CardDraft(title: '真实快照', content: 'first'),
        );
        await a.updateCard(
          card.id,
          const CardDraft(title: '真实快照', content: 'second'),
        );
        await a.writeLocalValue('fixture', 'encrypted-metadata');
        final bytes = await a.exportLocalState();
        await b.importLocalState(bytes);
        expect((await b.cardHistory(card.id)).map((r) => r.content), [
          'second',
          'first',
        ]);
        expect(await b.readLocalValue('fixture'), 'encrypted-metadata');
        final invalid = jsonDecode(utf8.decode(bytes)) as Map;
        (invalid['card_revisions'] as List).first['card_id'] = 'not-present';
        await expectLater(
          b.importLocalState(
            Uint8List.fromList(utf8.encode(jsonEncode(invalid))),
          ),
          throwsFormatException,
        );
        expect((await b.listCards()).single.content, 'second');
      } finally {
        await a.close();
        await b.close();
      }
    },
  );
}
