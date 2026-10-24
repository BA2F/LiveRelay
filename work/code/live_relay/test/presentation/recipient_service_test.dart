import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/identity/recipient_runtime.dart';
import 'package:live_relay/core/ports/recipient_store.dart';
import 'package:live_relay/presentation/controllers/recipient_service.dart';
import 'package:live_relay/presentation/pages/recipient_page.dart';

class _EmptyRecipientStore implements RecipientStore {
  @override
  Future<void> initialize() async {}

  @override
  Future<Uint8List?> readIdentity() async => null;

  @override
  Future<void> writeIdentity(Uint8List bytes) async {}

  @override
  Future<void> writePackage(String packageId, Uint8List bytes) async {}

  @override
  Future<List<SavedRecipientPackage>> savedPackages() async => const [];
}

void main() {
  test('defers synchronous runtime changes outside the calling turn', () async {
    final service = RecipientService(RecipientRuntime(_EmptyRecipientStore()));
    addTearDown(service.dispose);
    var notifications = 0;
    service.addListener(() => notifications++);

    final initialization = service.initialize();
    expect(notifications, 0);

    await initialization;
    await pumpEventQueue();
    expect(notifications, greaterThan(0));
  });

  testWidgets('opening recipient identity does not rebuild during build', (
    tester,
  ) async {
    final service = RecipientService(RecipientRuntime(_EmptyRecipientStore()));
    addTearDown(service.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: service,
          builder: (context, _) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => RecipientPage(service: service),
                ),
              ),
              child: const Text('打开接收者入口'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开接收者入口'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpAndSettle();
    expect(find.text('创建独立接收者身份'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
