import 'dart:io';

import 'package:live_relay/presentation/design_system/atoms.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/agent/agent_service.dart';
import 'package:live_relay/application/agent/agent_settings_service.dart';
import 'package:live_relay/application/ai/outbound_consent_service.dart';
import 'package:live_relay/application/agent/agent_review_service.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/application/vault_snapshot_query.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/application/vault_records_application.dart';
import 'package:live_relay/application/vault_backup_service.dart';
import 'package:live_relay/application/vault_merge_service.dart';
import 'package:live_relay/l10n/app_localizations.dart';
import 'package:live_relay/application/device_transfer_service.dart';
import 'package:live_relay/application/transfer/webdav_connection_service.dart';
import 'package:live_relay/core/ports/webdav_connection_repository.dart';
import 'package:live_relay/core/transfer/webdav_connection.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';

import 'support/session_fakes.dart';
import 'support/verification_fakes.dart';

import 'package:live_relay/application/release_preview.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/presentation/design_system/app_theme.dart';
import 'package:live_relay/presentation/pages/home_shell.dart';
import 'package:live_relay/presentation/pages/gate_page.dart';
import 'package:live_relay/presentation/pages/originals_page.dart';
import 'package:live_relay/presentation/pages/recycle_page.dart';
import 'package:live_relay/presentation/pages/device_transfer_page.dart';
import 'package:live_relay/presentation/pages/cradle_page.dart';
import 'package:live_relay/presentation/pages/profile_page.dart';
import 'package:live_relay/presentation/dialogs/card_dialogs.dart';
import 'package:live_relay/presentation/widgets/release_preview_panel.dart';
import 'package:live_relay/application/recipient_service.dart';
import 'package:live_relay/application/identity/recipient_runtime.dart';
import 'package:live_relay/infrastructure/identity/file_recipient_store.dart';

VaultBackupService snapshotBackup(VaultSession session) => VaultBackupService(
  session: session,
  archive: LifeVaultArchiveService(),
  restoreTransaction: () => throw UnsupportedError('UI snapshot only'),
);

/// 只切换“是否存在身份”的接收者服务，避免 UI 测试访问真实身份文件。
class FakeRecipientService extends RecipientService {
  FakeRecipientService()
    : super(
        RecipientRuntime(FileRecipientStore(() async => Directory.systemTemp)),
      );
  bool _exists = false;
  @override
  bool get exists => _exists;
  void setExists(bool value) {
    _exists = value;
    notifyListeners();
  }
}

class _NoConnection implements WebDavConnectionRepository {
  @override
  Future<WebDavConnection?> read() async => null;
  @override
  Future<void> write(WebDavConnection connection) async {}
  @override
  Future<void> clear() async {}
}

class SnapshotController extends AppController {
  SnapshotController({RecipientService? recipient})
    : this._(fixtureSession(), recipient: recipient);
  SnapshotController._(VaultSession session, {RecipientService? recipient})
    : this._withSettings(
        session,
        AgentSettingsService(TestAiSettings()),
        recipient: recipient,
      );
  SnapshotController._withSettings(
    VaultSession session,
    AgentSettingsService settings, {
    RecipientService? recipient,
  }) : this._withServices(
         session,
         settings,
         VaultContentService(vault: session, ocr: TestOcr()),
         VaultSnapshotQuery(session),
         recipient: recipient,
       );
  SnapshotController._withServices(
    VaultSession session,
    AgentSettingsService settings,
    VaultContentService content,
    VaultSnapshotQuery snapshots, {
    super.recipient,
  }) : super(
         records: VaultRecordsApplication(
           vault: session,
           content: content,
           snapshots: snapshots,
         ),
         session: session,
         backup: snapshotBackup(session),
         // The fixture never exports or imports through the medium; the
         // transfer service only needs wiring that satisfies the controller.
         transfer: DeviceTransferService(
           backup: snapshotBackup(session),
           archive: LifeVaultArchiveService(),
         ),
         merge: VaultMergeService(
           session: session,
           archive: LifeVaultArchiveService(),
           backup: snapshotBackup(session),
           restoreTransaction: () => throw UnsupportedError('UI fixture only'),
         ),
         webDav: WebDavConnectionService(_NoConnection()),
         content: content,
         agent: AgentService(
           vault: session,
           configuration: settings,
           provider: RecordingAi(),
         ),
         agentSettings: settings,
         outboundConsent: OutboundConsentService(TestOutboundConsent()),
         agentReview: AgentReviewService(session),
         snapshotQuery: snapshots,
         prepareEnvironment: () async {},
       ) {
    final now = DateTime.utc(2026, 10, 1);
    cards = [
      LifeCard(
        id: 'one',
        title: '备用钥匙',
        content: '鞋柜第二层',
        kind: CardKind.location,
        status: CardStatus.draft,
        tags: [],
        createdAt: now,
        updatedAt: now,
        revisionNumber: 1,
      ),
    ];
    credentials = [
      CredentialEntry(
        id: 'mail',
        title: '测试邮箱',
        username: 'test@example.com',
        secret: 'hidden-test-secret',
        website: '',
        notes: '',
        tags: [],
        createdAt: now,
        updatedAt: now,
        revisionNumber: 1,
      ),
    ];
  }
  @override
  VaultSessionState sessionState = VaultSessionState.loading;

  @override
  Future<void> refresh({
    String cardQuery = '',
    String credentialQuery = '',
  }) async {
    notifyListeners();
  }

  @override
  Future<List<CardSource>> cardSources(String id) async => [];
  @override
  Future<List<CardRelation>> cardRelations(String id) async => [];
  @override
  Future<ReleasePolicy> releasePolicy(String type, String id) async =>
      ReleasePolicy(recordType: type, recordId: id);
}

Widget app(
  AppController c,
  Widget page, {
  bool dark = false,
  double scale = 1,
  EdgeInsets insets = EdgeInsets.zero,
}) => ChangeNotifierProvider.value(
  value: c,
  child: MaterialApp(
    theme: dark ? LiveRelayTheme.dark() : LiveRelayTheme.light(),
    locale: const Locale('zh', 'CN'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale), viewInsets: insets),
      child: child!,
    ),
    home: page,
  ),
);

void main() {
  testWidgets(
    'recipient identity is reachable from settings, not the unlock page',
    (tester) async {
      final recipient = FakeRecipientService();
      final c = SnapshotController(recipient: recipient);
      addTearDown(c.dispose);

      await tester.pumpWidget(app(c, const UnlockVaultPage()));
      await tester.pumpAndSettle();
      expect(find.text('创建接收者身份'), findsNothing);
      expect(find.text('打开交接包'), findsOneWidget);

      await tester.pumpWidget(app(c, const Scaffold(body: ProfilePage())));
      await tester.pumpAndSettle();
      expect(find.text('创建接收者身份'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('资料库设置'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('资料库设置'));
      await tester.pumpAndSettle();
      final settingsScrollable = find
          .descendant(
            of: find.byType(BottomSheet),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        find.text('创建接收者身份'),
        200,
        scrollable: settingsScrollable,
      );
      await tester.pumpAndSettle();
      expect(find.text('创建接收者身份'), findsOneWidget);

      recipient.setExists(true);
      await tester.pumpAndSettle();
      expect(find.text('创建接收者身份'), findsNothing);
      expect(find.text('打开接收者身份'), findsOneWidget);

      await tester.pumpWidget(app(c, const UnlockVaultPage()));
      await tester.pumpAndSettle();
      expect(find.text('创建接收者身份'), findsNothing);
      expect(find.text('打开交接包'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'device transfer page gates export behind unlock and offers import',
    (tester) async {
      final c = SnapshotController();
      await tester.pumpWidget(app(c, const DeviceTransferPage()));
      await tester.pumpAndSettle();
      expect(find.text('设备间搬运'), findsOneWidget);
      expect(find.text('导出需要先解锁资料库。'), findsOneWidget);
      final exportButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '导出到介质目录'),
      );
      expect(exportButton.onPressed, isNull);
      final importButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '从介质导入（整库替换）'),
      );
      expect(importButton.onPressed, isNotNull);
      final topUpButton = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '从介质补齐原件（当前无欠件）'),
      );
      expect(topUpButton.onPressed, isNull);
      expect(find.text('云端：未配置'), findsOneWidget);
      expect(find.text('配置云端'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'cradle page shows cloud state, check-in button and plan editor',
    (tester) async {
      final c = SnapshotController();
      await tester.pumpWidget(app(c, const CradlePage()));
      await tester.pumpAndSettle();
      expect(find.text('报平安与自动交接'), findsOneWidget);
      expect(find.text('云端：未配置'), findsOneWidget);
      expect(find.text('最近报平安：尚无记录'), findsOneWidget);
      final checkInButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '报平安'),
      );
      expect(checkInButton.onPressed, isNull);
      expect(find.text('摇篮计划'), findsOneWidget);
      expect(find.textContaining('第 6 天开始提醒你'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('还没有接收者：先到「交接」页的「交给他人」添加。'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('还没有接收者：先到「交接」页的「交给他人」添加。'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'unmatched card search never clears recent home data and refresh retains query',
    (tester) async {
      final c = SnapshotController();
      await tester.pumpWidget(app(c, const HomeShell()));
      await tester.tap(find.text('卡片').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(SearchField).first, 'zzznomatch');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的卡片'), findsOneWidget);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的卡片'), findsOneWidget);
      await tester.tap(find.text('记录').last);
      await tester.pumpAndSettle();
      expect(find.text('备用钥匙'), findsOneWidget);
      await tester.tap(find.text('卡片').last);
      await tester.pumpAndSettle();
      expect(find.text('zzznomatch'), findsOneWidget);
      expect(find.text('没有匹配的卡片'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );

  testWidgets(
    'release secrets are masked initially, explicitly revealed and hidden after 30 seconds',
    (tester) async {
      final p = ReleasePreview(
        level: VisibilityLevel.secret,
        explanation: '密码默认遮挡',
        title: '邮箱',
        body: 'owner',
        secret: 'sensitive-secret',
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReleasePreviewPanel(preview: p)),
        ),
      );
      expect(find.text('sensitive-secret'), findsNothing);
      await tester.tap(find.text('显示密码 30 秒'));
      await tester.pump();
      expect(find.text('sensitive-secret'), findsOneWidget);
      await tester.pump(const Duration(seconds: 31));
      expect(find.text('sensitive-secret'), findsNothing);
    },
  );

  for (final dark in [false, true]) {
    testWidgets(
      '320dp and 200% text: all main pages, gates and keyboard can scroll without overflow ($dark)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 640);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final c = SnapshotController();
        await tester.pumpWidget(
          app(c, const HomeShell(), dark: dark, scale: 2),
        );
        await tester.pumpAndSettle();
        for (final label in ['卡片', '密码库', '交接', '我的', '记录']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: label);
        }
        for (final page in [
          const SetupVaultPage(),
          const UnlockVaultPage(),
          const OriginalsPage(),
          const RecyclePage(),
        ]) {
          await tester.pumpWidget(app(c, page, dark: dark, scale: 2));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$page');
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -600),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(
          app(
            c,
            Builder(
              builder: (context) => Scaffold(
                body: FilledButton(
                  onPressed: () => showCardEditor(context, c),
                  child: const Text('打开编辑'),
                ),
              ),
            ),
            dark: dark,
            scale: 2,
            insets: const EdgeInsets.only(bottom: 240),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开编辑'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );

    testWidgets('policy inspection supports 320dp and 200% text ($dark)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = SnapshotController();
      await tester.pumpWidget(
        app(
          c,
          Builder(
            builder: (context) => Scaffold(
              body: FilledButton(
                onPressed: () => showReleasePolicyDialog(
                  context,
                  c,
                  recordType: 'card',
                  recordId: 'one',
                  recordTitle: '备用钥匙',
                ),
                child: const Text('核对授权'),
              ),
            ),
          ),
          dark: dark,
          scale: 2,
        ),
      );
      await tester.tap(find.text('核对授权'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byType(DropdownButtonFormField<VisibilityLevel>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byType(DropdownButtonFormField<VisibilityLevel>).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('只知道有这条信息').last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });

    testWidgets(
      'main actions have readable contrast, labels and 48dp tap targets ($dark)',
      (tester) async {
        final c = SnapshotController();
        final handle = tester.ensureSemantics();
        await tester.pumpWidget(app(c, const HomeShell(), dark: dark));
        await tester.pumpAndSettle();
        for (final label in ['记录', '卡片', '密码库', '交接', '我的']) {
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(textContrastGuideline));
        }
        handle.dispose();
        await tester.pumpWidget(const SizedBox());
        c.dispose();
      },
    );
  }
}
