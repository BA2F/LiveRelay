import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/app_controller.dart';
import 'package:live_relay/infrastructure/app_composition.dart';
import 'package:live_relay/application/release_preview.dart';
import 'package:live_relay/core/domain/entities.dart';

import '../support/verification_fakes.dart';

const password = 'ux-verification-password-2026';
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late AppController c;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('liverelay-ux-');
    c = createAppController(
      dir,
      NoBiometrics(),
      TestOcr(),
      RecordingAi(),
      TestAiSettings(),
    );
    await c.initialize();
    await c.setupVault(password: password, usesChinesePassphrase: false);
  });
  tearDown(() async {
    await c.lock();
    c.dispose();
    await dir.delete(recursive: true);
  });

  test(
    'search projection stays isolated across mutations and refresh',
    () async {
      await c.createCard(
        const CardDraft(
          title: '备用钥匙',
          content: '鞋柜第二层',
          status: CardStatus.draft,
        ),
      );
      expect(c.findCards('zzznomatch'), isEmpty);
      expect(c.cards, hasLength(1));
      await c.refresh(cardQuery: 'zzznomatch');
      expect(c.findCards('zzznomatch'), isEmpty);
      expect(c.cards.single.title, '备用钥匙');
      await c.createCard(
        const CardDraft(title: 'zzznomatch 后来补充', content: '新的记录'),
      );
      expect(c.findCards('zzznomatch'), hasLength(1));
      expect(c.cards, hasLength(2));
      expect(c.findCards('钥匙', status: CardStatus.draft), hasLength(1));
    },
  );

  test(
    'unified password view retains canonical storage, revisions and recycling',
    () async {
      await c.saveCredential(
        const CredentialDraft(
          title: '邮箱',
          username: 'owner',
          secret: 'never-index-me',
        ),
      );
      final id = c.credentials.single.id;
      expect(c.cards, isEmpty);
      expect(
        c.findInformationCards('', passwordsOnly: true).single.recordId,
        id,
      );
      expect(c.findInformationCards('never-index-me'), isEmpty);
      await c.saveCredential(
        const CredentialDraft(
          title: '新邮箱',
          username: 'owner',
          secret: 'new-secret',
        ),
        id: id,
      );
      expect(c.findInformationCards('新邮箱').single.recordId, id);
      expect(await c.credentialHistory(id), hasLength(2));
      await c.lock();
      await c.unlockWithPassword(password);
      expect(c.findInformationCards('新邮箱').single.recordId, id);
      await c.trashCredential(id);
      expect(c.findInformationCards(''), isEmpty);
      await c.restoreCredential(id);
      expect(c.findInformationCards('').single.recordId, id);
      expect(c.cards, isEmpty);
    },
  );

  test('speech draft stays linked to encrypted audio after reopen', () async {
    await c.importOriginal(
      bytes: Uint8List.fromList(utf8.encode('fictional-audio')),
      originalName: 'speech-test.wav',
      mimeType: 'audio/wav',
      mediaKind: BlobMediaKind.audio,
    );
    final blobId = c.blobs.single.id;
    await c.saveSpeechDraft('人工校对后的文字', blobId: blobId);
    await c.lock();
    await c.unlockWithPassword(password);
    final draft = c.cards.firstWhere((v) => v.content == '人工校对后的文字');
    expect(draft.status, CardStatus.draft);
    final source = (await c.cardSources(draft.id)).single;
    expect(source.kind, SourceKind.audio);
    expect(source.blobId, blobId);
    expect(utf8.decode(await c.readOriginal(blobId)), 'fictional-audio');
  });

  test(
    'manual original path, revisions and recycle survive encrypted reopen',
    () async {
      final bytes = Uint8List.fromList(utf8.encode('original-test-content'));
      await c.importOriginal(
        bytes: bytes,
        originalName: '关联录音.m4a',
        mimeType: 'audio/mp4',
        mediaKind: BlobMediaKind.audio,
      );
      final blob = c.blobs.single;
      await c.createCardFromOriginal(
        blob.id,
        const CardDraft(
          title: '手工说明',
          content: '原始说明',
          status: CardStatus.draft,
        ),
      );
      final id = c.cards.firstWhere((v) => v.title == '手工说明').id;
      await c.confirmCard(id);
      await c.updateCard(id, const CardDraft(title: '手工说明', content: '补充后的说明'));
      expect((await c.cardHistory(id)).map((v) => v.content), [
        '补充后的说明',
        '原始说明',
        '原始说明',
      ]);
      expect((await c.cardSources(id)).any((s) => s.blobId == blob.id), isTrue);
      expect(await c.cardsForBlob(blob.id), hasLength(2));
      await c.saveReleasePolicy(
        ReleasePolicy(
          recordType: 'card',
          recordId: id,
          deceased: VisibilityLevel.summary,
        ),
      );
      await c.trashCard(id);
      expect(c.recycledCards.single.id, id);
      expect(c.executorCards, isEmpty);
      await c.lock();
      await c.unlockWithPassword(password);
      expect(c.recycledCards.single.id, id);
      await c.restoreCard(id);
      expect(c.recycledCards, isEmpty);
      expect(
        (await c.releasePolicy('card', id)).deceased,
        VisibilityLevel.summary,
      );
      expect((await c.cardHistory(id)), hasLength(3));
      expect(
        utf8.decode(await c.readOriginal(blob.id)),
        'original-test-content',
      );
      expect(
        await c.releasePolicy('card', c.cards.last.id),
        isA<ReleasePolicy>(),
      );
    },
  );

  test('credential recycle preserves all old secrets and policies', () async {
    await c.saveCredential(
      const CredentialDraft(title: '邮箱', username: 'owner', secret: 'old'),
    );
    final id = c.credentials.single.id;
    await c.saveCredential(
      const CredentialDraft(title: '邮箱', username: 'owner', secret: 'new'),
      id: id,
    );
    await c.trashCredential(id);
    expect(c.credentials, isEmpty);
    expect(c.recycledCredentials.single.secret, 'new');
    await c.restoreCredential(id);
    expect((await c.credentialHistory(id)).map((r) => r.secret), [
      'new',
      'old',
    ]);
    await c.purgeCredential(id);
    expect(await c.credentialHistory(id), isEmpty);
  });

  test('backup restores onto empty and locked vault, failed auth leaves current data', () async {
    await c.createCard(
      const CardDraft(
        title: '恢复样本',
        content: '加密备份内容',
        status: CardStatus.draft,
      ),
    );
    await c.createCard(const CardDraft(title: '回收样本', content: '旧内容'));
    await c.trashCard(c.cards.firstWhere((v) => v.title == '回收样本').id);
    final bytes = await c.exportVault(password);
    expect(c.lastBackupExport, isNull);
    await c.markBackupExported();
    expect(c.lastBackupExport, isNotNull);
    final targetDir = await Directory.systemTemp.createTemp(
      'liverelay-empty-restore-',
    );
    final target = createAppController(
      targetDir,
      NoBiometrics(),
      TestOcr(),
      RecordingAi(),
      TestAiSettings(),
    );
    try {
      await target.initialize();
      expect(target.sessionState, VaultSessionState.needsSetup);
      await expectLater(
        target.inspectBackup(bytes, 'wrong-password'),
        throwsA(anything),
      );
      expect(target.sessionState, VaultSessionState.needsSetup);
      final preview = await target.inspectBackup(bytes, password);
      expect(preview.cards, 1);
      expect(preview.recycledCards, 1);
      expect(preview.createdAt, isNotNull);
      await target.restoreVault(Uint8List.fromList(bytes), password);
      expect(target.cards.single.title, '恢复样本');
      expect(target.cards.single.status, CardStatus.draft);
      expect(target.recycledCards.single.title, '回收样本');
      await target.createCard(
        const CardDraft(title: '恢复后内容', content: '不能被失败恢复丢失'),
      );
      await target.lock();
      await expectLater(
        target.restoreVault(Uint8List.fromList(bytes), 'wrong-password'),
        throwsA(anything),
      );
      await target.unlockWithPassword(password);
      expect(target.cards, hasLength(2));
      await target.lock();
      await target.restoreVault(Uint8List.fromList(bytes), password);
      expect(target.cards, hasLength(1));
      expect(
        target.lastBackupExport,
        isNull,
      ); // export history belongs to this snapshot
    } finally {
      await target.lock();
      target.dispose();
      await targetDir.delete(recursive: true);
      bytes.fillRange(0, bytes.length, 0);
    }
  });

  test('all release levels preserve exact legacy output', () {
    final now = DateTime.utc(2026);
    final text = List.filled(90, '甲').join();
    final card = LifeCard(
      id: 'x',
      title: '标题',
      content: text,
      kind: CardKind.note,
      status: CardStatus.confirmed,
      tags: [],
      createdAt: now,
      updatedAt: now,
      revisionNumber: 1,
    );
    final entry = CredentialEntry(
      id: 'e',
      title: '账号名称',
      username: 'user',
      secret: 'sensitive',
      website: 'https://example.com',
      notes: 'private notes',
      tags: [],
      createdAt: now,
      updatedAt: now,
      revisionNumber: 1,
    );
    for (final level in VisibilityLevel.values) {
      final cp = ReleasePreview.card(card, level);
      final ep = ReleasePreview.credential(entry, level);
      expect(cp.title, level == VisibilityLevel.hidden ? null : '标题');
      expect(ep.title, level == VisibilityLevel.hidden ? null : '账号名称');
      expect(cp.body, switch (level) {
        VisibilityLevel.hidden => '',
        VisibilityLevel.existence => '存在一条此类信息，内容未授权。',
        VisibilityLevel.summary => '${text.substring(0, 80)}…',
        _ => text,
      });
      expect(ep.body, switch (level) {
        VisibilityLevel.hidden => '',
        VisibilityLevel.existence => '存在此账户，具体信息未授权。',
        VisibilityLevel.summary => 'user https://example.com',
        VisibilityLevel.full => 'private notes',
        _ => 'user',
      });
      expect(
        ep.secret,
        level.index >= VisibilityLevel.secret.index ? 'sensitive' : null,
      );
    }
  });
}
