import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/presentation/pages/handoff_page.dart';

void main() {
  testWidgets(
    'cancelling add recipient keeps fields alive through exit animation',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showAddRecipientDialog(context),
                child: const Text('打开添加接收者'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开添加接收者'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).at(0), '测试接收者');
      await tester.enterText(find.byType(TextField).at(1), 'test@example.com');
      await tester.pump();

      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
