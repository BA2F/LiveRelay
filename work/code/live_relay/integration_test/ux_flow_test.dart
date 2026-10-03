import 'package:live_relay/presentation/design_system/atoms.dart';

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/presentation/app.dart';
import 'package:live_relay/presentation/dialogs/card_dialogs.dart';
import 'package:live_relay/presentation/pages/recycle_page.dart';

import '../test/support/verification_fakes.dart';

const password = 'ux-verification-password-2026';
Future<Uint8List> fixtureImage() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  final paragraph =
      (ui.ParagraphBuilder(ui.ParagraphStyle(fontSize: 42))
            ..pushStyle(ui.TextStyle(color: Colors.black))
            ..addText('备用钥匙在鞋柜第二层\n测试私密备注'))
          .build()
        ..layout(const ui.ParagraphConstraints(width: 740));
  canvas.drawParagraph(paragraph, const Offset(24, 24));
  final picture = recorder.endRecording();
  final image = await picture.toImage(800, 240);
  final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer
      .asUint8List();
  image.dispose();
  picture.dispose();
  return bytes;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('complete encrypted UX on isolated Android verification package', (
    tester,
  ) async {
    WidgetController.hitTestWarningShouldBeFatal = true;
    final support = await getApplicationSupportDirectory();
    final directory = await support.createTemp('ux-suite-');
    final shots = Directory('${support.path}/ux-screenshots');
    await shots.create(recursive: true);
    final ai = RecordingAi();
    final settings = TestAiSettings();
    // Real SQLCipher, blob encryption and Android ML Kit; fake AI keeps the
    // verification offline and records exactly what would leave the device.
    final c = createAppController(
      directory,
      NoBiometrics(),
      null,
      ai,
      settings,
    );
    await c.initialize();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(value: c, child: const LiveRelayApp()),
    );
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    Future<void> shot(String name) async {
      await tester.pumpAndSettle();
      final bytes = await binding.takeScreenshot(name);
      await File('${shots.path}/$name.png').writeAsBytes(bytes);
    }

    Future<void> until(bool Function() done) async {
      for (var i = 0; i < 100 && !done(); i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(done(), isTrue);
      await tester.pumpAndSettle();
    }

    Future<void> tapText(String text) async {
      await tester.pumpAndSettle();
      if (text != '撤销' && find.byType(SnackBar).evaluate().isNotEmpty) {
        await tester.drag(find.byType(SnackBar).last, const Offset(0, 300));
        await tester.pumpAndSettle();
      }
      final base = find.text(text);
      if (base.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          base,
          350,
          scrollable: find.byType(Scrollable).first,
        );
      }
      final f = base.last;
      await Scrollable.ensureVisible(tester.element(f), alignment: 0.4);
      await tester.pumpAndSettle();
      await tester.tap(f);
      await tester.pumpAndSettle();
    }

    BuildContext currentContext() => tester.element(find.byType(Scaffold).last);
    Future<void> pop() async {
      await Navigator.of(currentContext()).maybePop();
      await tester.pumpAndSettle();
    }

    try {
      expect(find.text('已有加密备份？从备份恢复'), findsOneWidget);
      await shot('01-setup');
      await tapText('自定密码');
      await tester.enterText(find.byType(TextField).at(0), password);
      await tester.enterText(find.byType(TextField).at(1), password);
      await tapText('我已妥善保存口令');
      await tapText('创建并进入资料库');
      await until(() => c.isUnlocked);
      await shot('02-home-empty');
      await tapText('记一条');
      await tester.enterText(find.byType(TextField).first, '备用钥匙在鞋柜第二层');
      await shot('03-quick-editor-keyboard');
      await tapText('先保存');
      await until(() => c.cards.isNotEmpty);
      final id = c.cards.single.id;
      expect(c.cards.single.status, CardStatus.draft);
      expect(
        (await c.releasePolicy('card', id)).deceased,
        VisibilityLevel.hidden,
      );
      await shot('04-home-draft');
      await tapText('卡片');
      await tester.enterText(find.byType(SearchField).first, 'zzznomatch');
      await tester.pumpAndSettle();
      expect(find.text('没有匹配的卡片'), findsOneWidget);
      await c.refresh();
      await tester.pumpAndSettle();
      expect(find.text('zzznomatch'), findsOneWidget);
      await shot('05-search-empty');
      await tapText('记录');
      expect(find.text('备用钥匙在鞋柜第二层'), findsWidgets);
      await shot('06-home-search-isolated');
      await tapText('备用钥匙在鞋柜第二层');
      await tapText('本人确认这条内容');
      await until(() => c.cards.single.status == CardStatus.confirmed);
      await tapText('编辑这条信息');
      await tester.enterText(find.byType(TextField).first, '备用钥匙已移到书房抽屉');
      await tapText('内容已核对，确认保存');
      await until(() => c.cards.single.revisionNumber == 3);
      expect(c.cards.single.id, id);
      expect((await c.cardHistory(id)).last.content, '备用钥匙在鞋柜第二层');
      await shot('07-detail-edited');
      await tapText('查看完整修订历史');
      await shot('08-history');
      await tapText('关闭');
      await pop();
      await tapText('记一条');
      await tester.enterText(find.byType(TextField).first, '离开编辑时加密保留的测试资料');
      await pop();
      await tapText('加密保留');
      await until(() => c.cards.any((v) => v.content == '离开编辑时加密保留的测试资料'));
      expect(
        c.cards.firstWhere((v) => v.content == '离开编辑时加密保留的测试资料').status,
        CardStatus.draft,
      );
      await c.importOriginal(
        bytes: await fixtureImage(),
        originalName: '钥匙位置说明.png',
        mimeType: 'image/png',
        mediaKind: BlobMediaKind.image,
      );
      final blobId = c.blobs.single.id;
      await tapText('全部原件 · 1 个');
      await shot('09-originals');
      await tapText('钥匙位置说明.png');
      await shot('10-original-view');
      await tapText('整理内容');
      await tapText('手工整理关联说明');
      await tester.enterText(find.byType(TextField).first, '这张照片对应书房抽屉，手工填写');
      await tapText('先保存');
      await until(() => c.cards.any((v) => v.content.contains('手工填写')));
      final manual = c.cards.firstWhere((v) => v.content.contains('手工填写'));
      expect(
        (await c.cardSources(manual.id)).any((s) => s.blobId == blobId),
        isTrue,
      );
      await tapText('在本机识别文字');
      await until(() => c.blobs.single.ocrLines.isNotEmpty);
      expect(c.blobs.single.ocrText, contains('备用钥匙'));
      await shot('11-original-organize-ocr');
      // Save a mark on the actual OCR line, then prove no request before consent.
      final privateLine = c.blobs.single.ocrLines.firstWhere(
        (l) => l.text.contains('私密'),
      );
      await c.saveSensitiveMarks(blobId, [
        SensitiveMark(
          lineOrder: privateLine.order,
          kind: SensitiveFieldKind.note,
        ),
      ]);
      await tapText('检查 AI 外发内容');
      await shot('12-ai-unconfigured');
      await tapText('不使用 AI，手工整理');
      expect(find.text('想记下什么？'), findsOneWidget);
      await pop();
      await tapText('放弃修改');
      await tester.pumpAndSettle();
      await c.saveAiSettings(
        endpoint: 'https://verification.invalid/v1/chat/completions',
        model: 'verification-model',
        apiKey: 'test-key',
      );
      // Reopen to pick up configured state.
      await pop();
      await tapText('检查 AI 外发内容');
      await shot('13-ai-check');
      await tapText('检查并授权本次 AI 整理');
      expect(ai.requests, isEmpty);
      await shot('14-ai-single-consent');
      await tapText('拒绝');
      expect(ai.requests, isEmpty);
      await tapText('检查并授权本次 AI 整理');
      await tapText('仅允许本次');
      await until(() => ai.requests.length == 1 && !c.isBusy);
      expect(ai.requests.single.redactedText, isNot(contains('私密备注')));
      expect(ai.requests.single.redactedText, contains('[[NOTE_01]]'));
      expect(ai.requests.single.redactedText, contains('备用钥匙'));
      final generated = c.cards.firstWhere((v) => v.title == '识别资料整理');
      expect(generated.status, CardStatus.draft);
      expect(generated.content, contains('私密备注'));
      await pop();
      await pop();
      await c.saveCredential(
        const CredentialDraft(
          title: '验证邮箱',
          username: 'test@example.com',
          secret: 'synthetic-password',
          website: 'https://example.com',
          notes: '这是验证备注',
        ),
      );
      await tapText('密码库');
      expect(find.text('synthetic-password'), findsNothing);
      await shot('15-passwords-masked');
      final entry = c.credentials.single;
      await c.saveReleasePolicy(
        ReleasePolicy(
          recordType: 'credential',
          recordId: entry.id,
          incapacitated: VisibilityLevel.summary,
          deceased: VisibilityLevel.secret,
        ),
      );
      await c.saveReleasePolicy(
        ReleasePolicy(
          recordType: 'card',
          recordId: id,
          incapacitated: VisibilityLevel.summary,
          deceased: VisibilityLevel.full,
        ),
      );
      await tapText('交接');
      await shot('16-handoff-overview');
      await tapText('预览对方能看到什么');
      await shot('17-recipient-incapacitated');
      await tapText('身故');
      expect(find.text('synthetic-password'), findsNothing);
      await shot('18-recipient-deceased-masked');
      await tapText('显示密码 30 秒');
      expect(find.text('synthetic-password'), findsOneWidget);
      await tapText('立即遮挡密码');
      await pop();
      await tapText('打开独立模拟演示');
      await shot('19-simulation');
      await tapText('模拟临时失能');
      await tapText('确认模拟');
      await until(() => c.lifeState == LifeState.incapacitated);
      await pop();
      await tester.pumpAndSettle();
      final policyFuture = showReleasePolicyDialog(
        currentContext(),
        c,
        recordType: 'card',
        recordId: id,
        recordTitle: c.cards.firstWhere((v) => v.id == id).title,
      );
      await tester.pumpAndSettle();
      await shot('20-policy-precise-preview');
      await tapText('取消');
      await policyFuture;
      final detailFuture = showCardDetails(currentContext(), c, manual);
      await tester.pumpAndSettle();
      await shot('25-source-and-original-link');
      await tester.tap(find.byTooltip('更多操作'));
      await tester.pumpAndSettle();
      await tapText('移入回收区');
      await until(() => c.recycledCards.any((v) => v.id == manual.id));
      await detailFuture;
      await tapText('撤销');
      await until(() => c.recycledCards.isEmpty);
      await c.trashCard(manual.id);
      await c.trashCredential(entry.id);
      final recycleFuture = Navigator.of(currentContext())
          .push<void>(MaterialPageRoute(builder: (_) => const RecyclePage()));
      await tester.pumpAndSettle();
      await shot('21-recycle');
      await tester.tap(find.byTooltip('恢复卡片'));
      await until(() => c.recycledCards.isEmpty);
      await tester.tap(find.byTooltip('恢复密码'));
      await until(() => c.recycledCredentials.isEmpty);
      await pop();
      await recycleFuture;
      final bytes = await c.exportVault(password);
      await c.markBackupExported();
      final preview = await c.inspectBackup(bytes, password);
      expect(preview.originals, 1);
      await tester.tap(find.byTooltip('设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('资料库设置'));
      await tester.tap(find.text('资料库设置'));
      await tester.pumpAndSettle();
      await shot('22-settings-backup-status');
      await Navigator.of(currentContext()).maybePop();
      await tester.pumpAndSettle();
      await c.lock();
      await tester.pumpAndSettle();
      expect(find.text('从加密备份恢复'), findsOneWidget);
      await shot('23-unlock-restore');
      await c.restoreVault(Uint8List.fromList(bytes), password);
      await tester.pumpAndSettle();
      expect(c.blobs, hasLength(1));
      bytes.fillRange(0, bytes.length, 0);
      // Native small-screen and dark/font walks are also performed on the main APK.
      await shot('24-restored-home');
      expect(tester.takeException(), isNull);
      // Keep the isolated fixture path in the test output for forensic reruns.
      debugPrint('UX_VERIFICATION_DIRECTORY=${directory.path}');
      debugPrint('UX_SCREENSHOTS=${shots.path}');
    } finally {
      await c.lock();
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    }
  });
}
