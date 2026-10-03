import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/security/vault_key_manager.dart';
import 'package:live_relay/presentation/pages/gate_page.dart';

import 'formal_foundation_test.dart' show SetupController;
import 'ux_widget_test.dart' show app;

class FailingSetupController extends SetupController {
  @override
  Future<void> setupVault({
    required String password,
    required bool usesChinesePassphrase,
    int? wordCount,
    bool enableBiometric = false,
  }) async {
    creations++;
    lastError = '磁盘空间不足';
    throw StateError('create failed');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Finder creationButton() => find.ancestor(
    of: find.text('创建并进入资料库'),
    matching: find.byWidgetPredicate((widget) => widget is FilledButton),
  );

  test('short creation leaves no vault; eight Chinese characters create and unlock', () async {
    final directory = await Directory.systemTemp.createTemp(
      'liverelay-create-validation-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final manager = VaultKeyManager(directory);
    await expectLater(
      manager.create(canonicalPassword: '一二三四', passwordKind: 'custom'),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          '主密码至少需要 8 个字符',
        ),
      ),
    );
    expect(await manager.exists(), isFalse);
    final key = await manager.create(
      canonicalPassword: '一二三四五六七八',
      passwordKind: 'custom',
    );
    final reopened = await manager.unlock('一二三四五六七八');
    expect(reopened, key);
    await expectLater(
      manager.unlock('一二三四'),
      throwsA(isA<VaultUnlockException>()),
    );
    key.fillRange(0, key.length, 0);
    reopened.fillRange(0, reopened.length, 0);
  });

  testWidgets(
    'creation has live length and matching checks, and does not inherit unlock errors',
    (tester) async {
      final c = SetupController()..lastError = '主密码不正确或 Vault 已损坏';
      await tester.pumpWidget(app(c, const SetupVaultPage()));
      await tester.tap(find.text('自定密码'));
      await tester.pumpAndSettle();
      expect(find.text('至少 8 个字符，支持中文、字母、数字和符号'), findsOneWidget);
      expect(find.text('主密码不正确或 Vault 已损坏'), findsNothing);
      await tester.enterText(find.byType(TextField).at(0), '一二三四');
      await tester.pumpAndSettle();
      expect(find.text('主密码至少需要 8 个字符'), findsOneWidget);
      expect(tester.widget<FilledButton>(creationButton()).onPressed, isNull);
      expect(c.creations, 0);
      await tester.enterText(find.byType(TextField).at(0), '一二三四五六七八');
      await tester.pumpAndSettle();
      expect(find.text('密码长度符合要求'), findsOneWidget);
      expect(find.text('主密码至少需要 8 个字符'), findsNothing);
      await tester.enterText(find.byType(TextField).at(1), '12345678');
      await tester.pumpAndSettle();
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(tester.widget<FilledButton>(creationButton()).onPressed, isNull);
      await tester.enterText(find.byType(TextField).at(1), '一二三四五六七八');
      await tester.pumpAndSettle();
      expect(find.text('两次输入一致'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsNWidgets(2));
      await tester.ensureVisible(find.text('我已妥善保存口令'));
      await tester.tap(find.text('我已妥善保存口令'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(creationButton()).onPressed,
        isNotNull,
      );
      await tester.enterText(find.byType(TextField).at(0), '一二三四五六七九');
      await tester.pumpAndSettle();
      expect(
        tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
        isFalse,
      );
      expect(find.text('两次输入的密码不一致'), findsOneWidget);
      expect(tester.widget<FilledButton>(creationButton()).onPressed, isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets('creation failure stays on form and clears when editing', (
    tester,
  ) async {
    final c = FailingSetupController();
    await tester.pumpWidget(app(c, const SetupVaultPage()));
    await tester.tap(find.text('自定密码'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '一二三四五六七八');
    await tester.enterText(find.byType(TextField).at(1), '一二三四五六七八');
    await tester.ensureVisible(find.text('我已妥善保存口令'));
    await tester.tap(find.text('我已妥善保存口令'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('创建并进入资料库'));
    await tester.tap(find.text('创建并进入资料库'));
    await tester.pumpAndSettle();
    expect(find.text('磁盘空间不足'), findsOneWidget);
    expect(c.sessionState, VaultSessionState.needsSetup);
    await tester.enterText(find.byType(TextField).at(0), '修改密码后重试');
    await tester.pumpAndSettle();
    expect(find.text('磁盘空间不足'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    c.dispose();
  });
}
