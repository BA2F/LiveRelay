import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/presentation/design_system/app_theme.dart';
import 'package:live_relay/presentation/widgets/life_card_tile.dart';

void main() {
  testWidgets('life card atom renders domain state and accepts taps', (
    tester,
  ) async {
    var tapped = false;
    final now = DateTime.utc(2026, 9, 23);
    await tester.pumpWidget(
      MaterialApp(
        theme: LiveRelayTheme.light(),
        home: Scaffold(
          body: LifeCardTile(
            card: LifeCard(
              id: 'card-1',
              title: '房产证位置',
              content: '卧室衣柜顶层红色袋子',
              kind: CardKind.location,
              status: CardStatus.confirmed,
              tags: const ['重要'],
              createdAt: now,
              updatedAt: now,
              confirmedAt: now,
              revisionNumber: 1,
            ),
            onTap: () => tapped = true,
          ),
        ),
      ),
    );

    expect(find.text('房产证位置'), findsOneWidget);
    expect(find.text('已确认'), findsOneWidget);
    await tester.tap(find.text('房产证位置'));
    expect(tapped, isTrue);
  });
}
