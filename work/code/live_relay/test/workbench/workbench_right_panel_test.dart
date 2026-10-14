import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/agent/agent_review_service.dart';
import 'package:live_relay/application/agent/agent_service.dart';
import 'package:live_relay/application/agent/agent_settings_service.dart';
import 'package:live_relay/application/ai/outbound_consent_service.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/application/device_transfer_service.dart';
import 'package:live_relay/application/transfer/webdav_connection_service.dart';
import 'package:live_relay/application/vault_backup_service.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/application/vault_records_application.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/application/vault_snapshot_query.dart';
import 'package:live_relay/core/domain/card_references.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/webdav_connection_repository.dart';
import 'package:live_relay/core/transfer/webdav_connection.dart';
import 'package:live_relay/infrastructure/backup/life_vault_archive.dart';
import 'package:live_relay/presentation/workbench/workbench_right_panel.dart';

import '../support/session_fakes.dart';
import '../support/verification_fakes.dart';

class _NoConnection implements WebDavConnectionRepository {
  @override
  Future<WebDavConnection?> read() async => null;
  @override
  Future<void> write(WebDavConnection connection) async {}
  @override
  Future<void> clear() async {}
}

/// 右栏只读组件的最小夹具：沿用 SnapshotController 的装配方式，但把三块
/// 数据源换成罐头查询，避免在 widget 测试里碰真实数据库（fake-async 下
/// 真实 I/O 不会完成）。
class _LensController extends AppController {
  _LensController() : this._(fixtureSession());
  _LensController._(VaultSession session)
    : this._withSettings(session, AgentSettingsService(TestAiSettings()));
  _LensController._withSettings(
    VaultSession session,
    AgentSettingsService settings,
  ) : this._withServices(
        session,
        settings,
        VaultContentService(vault: session, ocr: TestOcr()),
        VaultSnapshotQuery(session),
      );
  _LensController._withServices(
    VaultSession session,
    AgentSettingsService settings,
    VaultContentService content,
    VaultSnapshotQuery snapshots,
  ) : super(
        records: VaultRecordsApplication(
          vault: session,
          content: content,
          snapshots: snapshots,
        ),
        session: session,
        backup: VaultBackupService(
          session: session,
          archive: LifeVaultArchiveService(),
          restoreTransaction: () => throw UnsupportedError('UI fixture only'),
        ),
        transfer: DeviceTransferService(
          backup: VaultBackupService(
            session: session,
            archive: LifeVaultArchiveService(),
            restoreTransaction: () =>
                throw UnsupportedError('UI fixture only'),
          ),
          archive: LifeVaultArchiveService(),
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
      );

  var unlocked = true;
  var lensCardId = 'A';
  List<CardSource> sources = const [];
  List<CardRevision> history = const [];
  List<LifeCard> cardsForBlobResult = const [];

  @override
  bool get isUnlocked => unlocked;
  @override
  Future<List<CardSource>> currentCardSources(String id) async =>
      id == lensCardId ? sources : const [];
  @override
  Future<List<CardRevision>> cardHistory(String id) async =>
      id == lensCardId ? history : const [];
  @override
  Future<List<LifeCard>> cardsForBlob(String blobId) async =>
      cardsForBlobResult;
}

Future<void> pumpLens(
  WidgetTester tester,
  AppController c,
  String? activeView,
  List<String> opened,
) => tester.pumpWidget(
  MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: WorkbenchRightPanel.width,
        child: WorkbenchRightPanel(
          controller: c,
          activeView: activeView,
          onOpen: opened.add,
        ),
      ),
    ),
  ),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('card lens lists sources, history and references read-only',
      (tester) async {
    final c = _LensController();
    final opened = <String>[];
    try {
      final now = DateTime.utc(2026, 10, 14, 9, 30);
      LifeCard card(String id, String title) => LifeCard(
        id: id,
        title: title,
        content: '$title 正文',
        kind: CardKind.note,
        status: CardStatus.confirmed,
        tags: const [],
        createdAt: now,
        updatedAt: now,
        revisionNumber: 8,
      );
      c.cards = [card('A', '卡片甲'), card('B', '卡片乙')];
      c.cardReferences = const [CardReference('A', 'B')];
      c.blobs = [
        VaultBlob(
          id: 'blob-1',
          originalName: 'note.txt',
          mediaKind: BlobMediaKind.document,
          mimeType: 'text/plain',
          relativePath: 'blobs/blob-1.blob',
          byteLength: 11,
          sha256: 'fixture',
          createdAt: now,
        ),
      ];
      c.sources = [
        CardSource(
          label: '本人输入',
          kind: SourceKind.ownerInput,
          excerpt: '甲正文',
          createdAt: now,
        ),
        CardSource(
          label: '本人引用 · note.txt',
          kind: SourceKind.ownerInput,
          excerpt: '',
          createdAt: now,
          blobId: 'blob-1',
        ),
      ];
      c.history = [
        for (var number = 8; number >= 1; number--)
          CardRevision(
            id: number,
            cardId: 'A',
            number: number,
            title: '卡片甲',
            content: '甲正文 $number',
            tags: const [],
            status: CardStatus.confirmed,
            sourceKind: SourceKind.ownerInput,
            sourceLabel: '本人输入',
            changeNote: number == 8 ? '添加原件引用 · note.txt' : '改动 $number',
            createdAt: now,
          ),
      ];

      await pumpLens(tester, c, 'card/A', opened);
      await tester.pumpAndSettle();

      // 来源：文本来源不可点；挂原件的一行可点跳到原件标签。
      expect(find.text('来源 · 2'), findsOneWidget);
      expect(find.text('本人输入'), findsOneWidget);
      expect(find.text('本人引用 · note.txt'), findsOneWidget);
      await tester.tap(find.text('本人输入'));
      await tester.pump();
      expect(opened, isEmpty);
      await tester.tap(find.text('本人引用 · note.txt'));
      await tester.pump();
      expect(opened, ['source/blob-1']);
      opened.clear();

      // 历史：只列最近 5 条（8..4），其余走完整历史；不渲染正文。
      expect(find.text('历史 · 最近 5 条'), findsOneWidget);
      expect(find.textContaining('修订 8 ·'), findsOneWidget);
      expect(find.textContaining('修订 4 ·'), findsOneWidget);
      expect(find.textContaining('修订 3 ·'), findsNothing);
      expect(find.textContaining('甲正文'), findsNothing);
      await tester.tap(find.text('打开完整历史'));
      await tester.pump();
      expect(opened, ['history/A']);
      opened.clear();

      // 引用：出链可点跳卡片；条目标题取目标卡标题。
      expect(find.text('引用 · 1'), findsOneWidget);
      await tester.tap(find.text('卡片乙'));
      await tester.pump();
      expect(opened, ['card/B']);
      opened.clear();

      // 卡片修订变化（自动保存）触发历史重查，不换标签也刷新。
      c.cards = [
        LifeCard(
          id: 'A',
          title: '卡片甲',
          content: '甲正文',
          kind: CardKind.note,
          status: CardStatus.confirmed,
          tags: const [],
          createdAt: now,
          updatedAt: now,
          revisionNumber: 9,
        ),
        card('B', '卡片乙'),
      ];
      c.history = [
        CardRevision(
          id: 9,
          cardId: 'A',
          number: 9,
          title: '卡片甲',
          content: '甲正文 9',
          tags: const [],
          status: CardStatus.confirmed,
          sourceKind: SourceKind.ownerInput,
          sourceLabel: '本人输入',
          changeNote: '第九次改动',
          createdAt: now,
        ),
        ...c.history,
      ];
      await pumpLens(tester, c, 'card/A', opened);
      await tester.pumpAndSettle();
      expect(find.textContaining('修订 9 · 第九次改动'), findsOneWidget);

      // 被引用：乙视角。
      await pumpLens(tester, c, 'card/B', opened);
      await tester.pumpAndSettle();
      expect(find.text('被引用 · 1'), findsOneWidget);
      await tester.tap(find.text('卡片甲'));
      await tester.pump();
      expect(opened, ['card/A']);
      opened.clear();

      // 原件回收／删除两态：文案区分且不可再点开。
      c.recycledBlobIds = const {'blob-1'};
      await pumpLens(tester, c, 'card/A', opened);
      await tester.pumpAndSettle();
      expect(find.textContaining('已移入回收区'), findsOneWidget);
      await tester.tap(find.text('本人引用 · note.txt'));
      await tester.pump();
      expect(opened, isEmpty);
      c.recycledBlobIds = const {};
      c.blobs = const [];
      await pumpLens(tester, c, 'card/A', opened);
      await tester.pumpAndSettle();
      expect(find.textContaining('原件已删除'), findsOneWidget);
      await tester.tap(find.text('本人引用 · note.txt'));
      await tester.pump();
      expect(opened, isEmpty);

      // 非对象标签与锁定后：空态且不崩（锁定时投影清空，与真实行为一致）。
      await pumpLens(tester, c, 'settings', opened);
      expect(find.text('当前标签没有跟随信息'), findsOneWidget);
      c.unlocked = false;
      c.cards = const [];
      await pumpLens(tester, c, 'card/A', opened);
      await tester.pumpAndSettle();
      expect(find.text('当前标签没有跟随信息'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      c.dispose();
    }
  });

  testWidgets('source lens shows metadata and its referencing cards',
      (tester) async {
    final c = _LensController();
    final opened = <String>[];
    try {
      final now = DateTime.utc(2026, 10, 14, 9, 30);
      c.blobs = [
        VaultBlob(
          id: 'blob-1',
          originalName: 'note.txt',
          mediaKind: BlobMediaKind.document,
          mimeType: 'text/plain',
          relativePath: 'blobs/blob-1.blob',
          byteLength: 2048,
          sha256: 'fixture',
          createdAt: now,
        ),
      ];
      final card = LifeCard(
        id: 'A',
        title: '卡片甲',
        content: '甲正文',
        kind: CardKind.note,
        status: CardStatus.confirmed,
        tags: const [],
        createdAt: now,
        updatedAt: now,
        revisionNumber: 3,
      );
      c.cards = [card];
      c.cardsForBlobResult = [card];

      await pumpLens(tester, c, 'source/blob-1', opened);
      await tester.pumpAndSettle();
      expect(find.text('note.txt'), findsOneWidget);
      expect(find.textContaining('文档 · 2 KB'), findsOneWidget);
      expect(find.text('引用它的卡片 · 1'), findsOneWidget);
      await tester.tap(find.text('卡片甲'));
      await tester.pump();
      expect(opened, ['card/A']);
      opened.clear();

      // 切换标签再回来，模拟数据变化后的重新挂载（面板按标签实例加载一次）。
      await pumpLens(tester, c, 'settings', opened);
      await tester.pump();
      c.cardsForBlobResult = const [];
      await pumpLens(tester, c, 'source/blob-1', opened);
      await tester.pumpAndSettle();
      expect(find.text('还没有卡片引用这个原件'), findsOneWidget);

      await pumpLens(tester, c, 'settings', opened);
      await tester.pump();
      c.cardsForBlobResult = [card];
      c.recycledBlobIds = const {'blob-1'};
      await pumpLens(tester, c, 'source/blob-1', opened);
      await tester.pumpAndSettle();
      expect(find.text('原件已移入回收区'), findsOneWidget);
      c.recycledBlobIds = const {};

      await pumpLens(tester, c, 'settings', opened);
      await tester.pump();
      c.blobs = const [];
      await pumpLens(tester, c, 'source/blob-1', opened);
      await tester.pumpAndSettle();
      expect(find.text('原件已删除'), findsOneWidget);
      expect(find.text('来源关系仍在卡片与修订历史中保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      c.dispose();
    }
  });
}
