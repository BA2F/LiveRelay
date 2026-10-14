import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/vault_merge.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/infrastructure/transfer/directory_transfer_medium.dart';

import '../support/verification_fakes.dart';

const _password = 'fictional-merge-controller';

AppController controller(Directory root) => createAppController(
  root,
  NoBiometrics(),
  TestOcr(),
  RecordingAi(),
  TestAiSettings(),
);

/// 同库两副本走到"各自改过同一张卡"的分叉点：A 建库导出，B 替换导入。
/// 介质目录在 [medium]，返回时 A、B 停在同一起点。
Future<void> forkSetup(
  AppController a,
  AppController b,
  Directory medium,
) async {
  await medium.create(recursive: true);
  await a.initialize();
  final recovery = await a.generateRecovery();
  await a.setupModernVault(
    password: _password,
    recoveryText: recovery,
    recoveryConfirmation: recovery,
  );
  await a.createCard(
    const CardDraft(title: '备用钥匙', content: '放在鞋柜第二层。'),
  );
  final mediumA = DirectoryTransferMedium(medium);
  await a.exportToMedium(mediumA, _password);

  await b.initialize();
  final scan = await b.scanTransferMedium(mediumA);
  await b.importFromMedium(
    mediumA,
    databaseName: scan.databases.single.name,
    credential: _password,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'controller merge round trip: a fork is merged, marked and resolved by adopting the other version',
    () async {
      final root = await Directory.systemTemp.createTemp('relay-merge-ctl-');
      addTearDown(() => root.delete(recursive: true));
      final medium = Directory('${root.path}/medium');
      final a = controller(Directory('${root.path}/a'));
      final b = controller(Directory('${root.path}/b'));
      try {
        await forkSetup(a, b, medium);

        // A 改本机版；B 改同一张卡并新增一张。
        final cardIdOnA = a.cards.single.id;
        await a.updateCard(
          cardIdOnA,
          const CardDraft(title: '备用钥匙', content: 'A 侧改过：鞋柜第三层。', status: CardStatus.confirmed),
          changeNote: 'A 侧修改',
        );
        await b.updateCard(
          b.cards.single.id,
          const CardDraft(title: '备用钥匙', content: 'B 侧改过：换了新锁。', status: CardStatus.confirmed),
          changeNote: 'B 侧修改',
        );
        await b.createCard(
          const CardDraft(title: 'B 新增的卡', content: '只有 B 有。'),
        );
        final mediumB = DirectoryTransferMedium(medium);
        await b.exportToMedium(mediumB, _password);

        // A 合并导入：触发条件（同 vaultId）在控制器层可见。
        final scan = await a.scanTransferMedium(mediumB);
        final package = scan.databases.single;
        expect(package.vaultId, isNotNull);
        expect(await a.archiveVaultId(), package.vaultId);

        final report = await a.mergeFromMedium(
          mediumB,
          databaseName: package.name,
          credential: _password,
        );
        expect(report.importedCards, 1);
        expect(report.forkedCards, 1);
        expect(report.conflicts, hasLength(1));
        expect(report.unmergedCategories, isNotEmpty);

        // 分叉的卡保持本机版并带标记；B 的新卡进来了。
        expect(
          a.cards.firstWhere((c) => c.id == cardIdOnA).content,
          'A 侧改过：鞋柜第三层。',
        );
        expect(a.cards.any((c) => c.title == 'B 新增的卡'), isTrue);
        final conflict = a.mergeConflicts[cardIdOnA];
        expect(conflict, isNotNull);
        expect(conflict!.kind, MergeConflictKind.fork);
        expect(conflict.foreignHead, isNotNull);

        // 采用另一台设备的版本：写一条新修订，标记清除。
        await a.adoptForeignMergeVersion(cardIdOnA);
        expect(a.mergeConflicts, isEmpty);
        expect(
          a.cards.firstWhere((c) => c.id == cardIdOnA).content,
          'B 侧改过：换了新锁。',
        );
      } finally {
        await a.lock().catchError((_) {});
        a.dispose();
        await b.lock().catchError((_) {});
        b.dispose();
      }
    },
  );

  test('editing a merged card directly clears its merge marker', () async {
    final root = await Directory.systemTemp.createTemp('relay-merge-ctl-');
    addTearDown(() => root.delete(recursive: true));
    final medium = Directory('${root.path}/medium');
    final a = controller(Directory('${root.path}/a'));
    final b = controller(Directory('${root.path}/b'));
    try {
      await forkSetup(a, b, medium);
      final cardIdOnA = a.cards.single.id;
      await a.updateCard(
        cardIdOnA,
        const CardDraft(title: '备用钥匙', content: '本机版。', status: CardStatus.confirmed),
        changeNote: '本机修改',
      );
      await b.updateCard(
        b.cards.single.id,
        const CardDraft(title: '备用钥匙', content: '对方版。', status: CardStatus.confirmed),
        changeNote: '对方修改',
      );
      final mediumB = DirectoryTransferMedium(medium);
      await b.exportToMedium(mediumB, _password);
      final scan = await a.scanTransferMedium(mediumB);
      await a.mergeFromMedium(
        mediumB,
        databaseName: scan.databases.single.name,
        credential: _password,
      );
      expect(a.mergeConflicts, hasLength(1));

      // 用户直接编辑即视为已做选择。
      await a.updateCard(
        cardIdOnA,
        const CardDraft(title: '备用钥匙', content: '本机继续编辑。', status: CardStatus.confirmed),
        changeNote: '继续编辑',
      );
      expect(a.mergeConflicts, isEmpty);
      expect(
        a.cards.firstWhere((c) => c.id == cardIdOnA).content,
        '本机继续编辑。',
      );
    } finally {
      await a.lock().catchError((_) {});
      a.dispose();
      await b.lock().catchError((_) {});
      b.dispose();
    }
  });
}
