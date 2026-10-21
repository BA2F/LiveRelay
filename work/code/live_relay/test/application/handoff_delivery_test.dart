import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/handoff_delivery_service.dart';
import 'package:live_relay/application/handoff_view_service.dart';
import 'package:live_relay/application/local_handoff_service.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/security/pickup_code.dart';
import 'package:live_relay/core/transfer/webdav_connection.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

import '../support/session_fakes.dart';

final _connection = WebDavConnection(
  baseUrl: Uri.parse('http://example.com:3923/owner/'),
  username: 'owner',
  password: 'password',
);

Future<HandoffDeliveryService> _unlockedService(Directory root) async {
  final repository = SqliteVaultRepository(AppDatabase.inMemory());
  final session = fixtureSession(
    directory: Directory('${root.path}/owner'),
    openRepository: (_, _) async => repository,
  );
  await session.prepare();
  await session.openWithKey(Uint8List(32));
  session.markUnlocked();
  addTearDown(session.close);
  final handoff = LocalHandoffService(session, originals: session);
  return HandoffDeliveryService(
    session: session,
    handoff: handoff,
    view: HandoffViewService(() async => File('${root.path}/view.json')),
  );
}

void main() {
  test('pickup codes generate, normalize and format', () {
    final code = PickupCode.generate();
    expect(code.length, 12);
    expect(PickupCode.isValid(code), isTrue);
    final formatted = PickupCode.format(code);
    expect(formatted.split('-'), hasLength(3));
    expect(formatted.replaceAll('-', ''), code);
    expect(PickupCode.normalize(' ${formatted.toLowerCase()} '), code);
    expect(PickupCode.isValid('short'), isFalse);
    expect(PickupCode.format('custom-code-1234'), 'CUSTOMCODE1234');
  });

  test('delivery records keep scope, draft and status', () async {
    final root = await Directory.systemTemp.createTemp('handoff-delivery-');
    addTearDown(() => root.delete(recursive: true));
    final service = await _unlockedService(root);

    final delivery = await service.add(
      label: '妻子',
      email: 'wife@example.com',
      scope: [
        const ScopedRecord('card', 'card-1', VisibilityLevel.full),
        const ScopedRecord(
          'credential',
          'credential-1',
          VisibilityLevel.secret,
        ),
      ],
      connection: _connection,
    );
    expect(delivery.status, DeliveryStatus.draft);
    expect(delivery.packageName, startsWith('liverelay-handoff-'));
    expect(delivery.body, contains(PickupCode.format(delivery.pickupCode)));
    expect(delivery.body, contains(delivery.packageName));
    expect(
      HandoffDeliveryService.bodyContainsCode(
        delivery.body,
        delivery.pickupCode,
      ),
      isTrue,
    );

    final list = await service.list();
    expect(list, hasLength(1));
    expect(list.single.scope, hasLength(2));
    expect(list.single.scope.first.type, 'card');

    final parsed = HandoffDelivery.parse(delivery.toJson());
    expect(parsed.body, delivery.body);
    expect(parsed.scope.last.level, VisibilityLevel.secret);

    final uploaded = delivery.copyWith(
      uploadedAt: delivery.updatedAt.add(const Duration(seconds: 1)),
    );
    expect(uploaded.status, DeliveryStatus.uploaded);
    final changed = uploaded.copyWith(
      updatedAt: uploaded.uploadedAt!.add(const Duration(seconds: 1)),
    );
    expect(changed.status, DeliveryStatus.needsUpdate);
    expect(changed.copyWith(enabled: false).status, DeliveryStatus.disabled);

    final newCode = PickupCode.generate();
    final replaced = HandoffDeliveryService.replaceCode(
      delivery.body,
      delivery.pickupCode,
      newCode,
    );
    expect(HandoffDeliveryService.bodyContainsCode(replaced, newCode), isTrue);
    expect(
      HandoffDeliveryService.bodyContainsCode(replaced, delivery.pickupCode),
      isFalse,
    );
  });

  test('plan contains enabled recipients and their drafts', () async {
    final root = await Directory.systemTemp.createTemp('handoff-delivery-');
    addTearDown(() => root.delete(recursive: true));
    final service = await _unlockedService(root);
    final first = await service.add(
      label: '妻子',
      email: 'wife@example.com',
      scope: const [],
      connection: _connection,
    );
    final second = await service.add(
      label: '弟弟',
      email: 'brother@example.com',
      scope: const [],
      connection: _connection,
    );

    final plan = service.buildPlan(
      [
        first.copyWith(uploadedAt: first.updatedAt),
        second.copyWith(enabled: false),
      ],
      const CradleTiming(ownerEmail: 'owner@example.com'),
      _connection,
    );
    expect(plan.toJson()['version'], 2);
    expect(plan.recipients, hasLength(1));
    expect(plan.recipients.single.label, '妻子');
    expect(plan.recipients.single.subject, first.subject);
    expect(plan.recipients.single.body, first.body);
    expect(plan.recipients.single.packageName, first.packageName);

    expect(
      () => service.buildPlan(
        [first],
        const CradleTiming(ownerEmail: ''),
        _connection,
      ),
      throwsFormatException,
    );
    expect(
      HandoffDeliveryService.packageUrl(
        _connection,
        first.packageName,
      ).toString(),
      'http://example.com:3923/owner/${first.packageName}',
    );
  });
}
