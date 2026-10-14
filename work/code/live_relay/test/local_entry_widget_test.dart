import 'package:flutter/material.dart' hide SnapshotController;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/ports/development_controls.dart';
import 'package:live_relay/l10n/app_localizations.dart';
import 'package:live_relay/presentation/pages/profile_page.dart';

import 'ux_widget_test.dart' show SnapshotController;

class DemoEntry implements DevelopmentControls {
  int activations = 0;
  @override
  void activate() {
    activations++;
  }
}

void main() {
  testWidgets(
    'seven version taps activate only an explicitly injected demo entry',
    (tester) async {
      final c = SnapshotController()..sessionState = VaultSessionState.unlocked;
      final demo = DemoEntry();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AppController>.value(value: c),
            Provider<DevelopmentControls>.value(value: demo),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.textContaining('1.0.0'), 200);
      await tester.pumpAndSettle();
      for (var i = 0; i < 6; i++) {
        await tester.tap(find.textContaining('1.0.0'));
        await tester.pump();
      }
      expect(demo.activations, 0);
      await tester.tap(find.textContaining('1.0.0'));
      await tester.pump();
      expect(demo.activations, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        ChangeNotifierProvider<AppController>.value(
          value: c,
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: ProfilePage()),
          ),
        ),
      );
      await tester.scrollUntilVisible(find.textContaining('1.0.0'), 200);
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await tester.tap(find.textContaining('1.0.0'));
        await tester.pump();
      }
      expect(tester.takeException(), isNull);
      expect(demo.activations, 1);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
