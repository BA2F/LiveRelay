import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_preferences.dart';
import 'package:live_relay/application/workbench/workbench_layout.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/workbench/dock_surface.dart';

import '../test/support/verification_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native desktop edits and layout persist in encrypted vault without confirming drafts',
    (tester) async {
      final root = await Directory.systemTemp.createTemp(
        'liverelay-workbench-test-',
      );
      final c = createAppController(
        root,
        NoBiometrics(),
        TestOcr(),
        RecordingAi(),
        TestAiSettings(),
      );
      final p = AppPreferences(File('${root.path}/device-preferences.json'));
      final screenshotKey = GlobalKey();
      try {
        await c.initialize();
        await c.setupVault(
          password: 'fictional-workbench-2026',
          usesChinesePassphrase: false,
        );
        await c.createCard(
          const CardDraft(
            title: '虚构资料位置',
            content: '蓝色文件夹',
            status: CardStatus.draft,
          ),
        );
        final id = c.cards.single.id;
        await p.finishOnboarding();
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: c),
              ChangeNotifierProvider.value(value: p),
            ],
            child: RepaintBoundary(
              key: screenshotKey,
              child: const LiveRelayApp(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('选择你的工作台'), findsOneWidget);
        await tester.tap(find.text('资料工作台'));
        await tester.pumpAndSettle();
        final summary = find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == '总结',
        );
        await tester.enterText(summary.first, '编辑后仍待确认');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(c.cards.single.content, '编辑后仍待确认');
        expect(c.cards.single.status, CardStatus.draft);
        expect(await c.cardHistory(id), hasLength(2));
        await tester.ensureVisible(find.byTooltip('在新标签编辑').first);
        await tester.tap(find.byTooltip('在新标签编辑').first);
        await tester.pumpAndSettle();
        final surface = tester.widget<DockSurface>(find.byType(DockSurface));
        final cardTab = surface.layout.groups
            .expand((g) => g.tabs)
            .firstWhere((v) => v.startsWith('card/'));
        surface.layout.move(
          cardTab,
          surface.layout.groups.last.id,
          DockPlacement.center,
        );
        await tester.pumpAndSettle();
        expect(summary, findsNWidgets(2));
        await tester.enterText(summary.last, '两个视图一致');
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        for (final field in tester.widgetList<TextField>(summary)) {
          expect(field.controller!.text, '两个视图一致');
        }
        await tester.tap(find.byTooltip('确认当前卡片').last);
        await tester.pumpAndSettle();
        expect(c.cards.single.status, CardStatus.confirmed);
        expect(
          (await c.releasePolicy('card', id)).visibleAt(LifeState.deceased),
          VisibilityLevel.hidden,
        );
        surface.layout.move('changes', '', DockPlacement.floating);
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        final state = await c.readWorkbenchState();
        expect(state, contains('floating'));
        final evidencePath =
            Platform.environment['LIVERELAY_WORKBENCH_EVIDENCE'];
        if (evidencePath != null) {
          final dir = Directory(evidencePath);
          await dir.create(recursive: true);
          final boundary =
              screenshotKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary;
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${dir.path}/native-workbench.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        }
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        await c.unlockWithPassword('fictional-workbench-2026');
        expect(c.cards.single.content, '两个视图一致');
        expect(await c.readWorkbenchState(), state);
        expect(await c.cardHistory(id), hasLength(4));
        await c.trashCard(id);
        await c.restoreCard(id);
        expect(c.cards.single.content, '两个视图一致');
        final deviceText = await File('${root.path}/device-preferences.json')
            .readAsString();
        expect(deviceText, isNot(contains(id)));
        expect(deviceText, isNot(contains('两个视图一致')));
        if (evidencePath != null) {
          await File('$evidencePath/verification.json').writeAsString(
            jsonEncode({
              'platform': Platform.operatingSystem,
              'fixture': true,
              'autosaveDraft': true,
              'sharedEdit': true,
              'confirmationDoesNotGrantRelease': true,
              'encryptedReopen': true,
              'layoutPersistence': true,
              'revisions': 4,
              'recycleRestore': true,
            }),
          );
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        await c.lock();
        c.dispose();
        p.dispose();
        await root.delete(recursive: true);
      }
    },
  );
}
