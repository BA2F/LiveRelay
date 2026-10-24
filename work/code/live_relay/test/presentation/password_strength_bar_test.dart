import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/password_strength.dart';
import 'package:live_relay/l10n/app_localizations.dart';
import 'package:live_relay/presentation/design_system/password_strength_bar.dart';

int _filledSegments(WidgetTester tester) {
  return tester
      .widgetList<Container>(find.byType(Container))
      .map((container) => container.decoration)
      .whereType<BoxDecoration>()
      .where((decoration) => decoration.color != Colors.transparent)
      .length;
}

Future<void> _pump(WidgetTester tester, PasswordStrength strength) {
  return tester.pumpWidget(
    MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: PasswordStrengthBar(strength: strength)),
    ),
  );
}

void main() {
  testWidgets('weak fills one segment and labels it', (tester) async {
    await _pump(tester, PasswordStrength.weak);
    expect(_filledSegments(tester), 1);
    expect(find.text('弱'), findsOneWidget);
  });

  testWidgets('medium fills two segments and labels it', (tester) async {
    await _pump(tester, PasswordStrength.medium);
    expect(_filledSegments(tester), 2);
    expect(find.text('中'), findsOneWidget);
  });

  testWidgets('strong fills three segments and labels it', (tester) async {
    await _pump(tester, PasswordStrength.strong);
    expect(_filledSegments(tester), 3);
    expect(find.text('强'), findsOneWidget);
  });
}
