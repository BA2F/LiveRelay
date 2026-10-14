import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/workbench/card_edit_sessions.dart';
import 'package:live_relay/application/workbench/workbench_tabs.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/application/workbench/card_references.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

LifeCard fixture() => LifeCard(
  id: 'fixture',
  title: '标题',
  content: '原文',
  kind: CardKind.note,
  status: CardStatus.draft,
  tags: [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revisionNumber: 1,
);
void main() {
  test('references preserve existing storage, validate targets, and survive backup snapshots', () async {
    final repo = SqliteVaultRepository(AppDatabase.inMemory());
    final copy = SqliteVaultRepository(AppDatabase.inMemory());
    try {
      final a = await repo.createCard(
        const CardDraft(title: 'A', content: '来源 A'),
      );
      final b = await repo.createCard(
        const CardDraft(title: 'B', content: '来源 B'),
      );
      final links = CardReferenceStore(repo);
      await links.replace(a.id, [b.id, b.id]);
      expect((await links.read()).single.to, b.id);
      expect(await repo.relationsForCard(a.id), isEmpty);
      await expectLater(links.replace(a.id, [a.id]), throwsFormatException);
      await expectLater(
        links.replace(a.id, ['missing']),
        throwsFormatException,
      );
      expect((await links.read()).single.to, b.id);
      await copy.importLocalState(await repo.exportLocalState());
      expect((await CardReferenceStore(copy).read()).single.from, a.id);
      await repo.trashCard(b.id);
      await repo.restoreCard(b.id);
      expect((await links.read()).single.to, b.id);
      expect(
        (await repo.getReleasePolicy(
          'card',
          a.id,
        )).visibleAt(LifeState.deceased),
        VisibilityLevel.hidden,
      );
    } finally {
      await repo.close();
      await copy.close();
    }
  });
  test('tabs keep one entry per object, activate, reorder and restore exactly once', () {
    final tabs = WorkbenchTabs();
    tabs.open('card/fixture/one');
    tabs.open('agent');
    tabs.open('card/fixture/one');
    expect(tabs.tabs, ['card/fixture/one', 'agent']);
    expect(tabs.active, 'card/fixture/one');
    tabs.move('agent', 0);
    expect(tabs.tabs, ['agent', 'card/fixture/one']);
    tabs.selectSection('passwords');
    tabs.setRightCollapsed(true);
    tabs.close('agent');
    expect(tabs.tabs, ['card/fixture/one']);
    expect(tabs.active, 'card/fixture/one');
    final restored = WorkbenchTabs();
    restored.restore(
      jsonDecode(jsonEncode(tabs.toJson())) as Map<String, dynamic>,
    );
    expect(restored.tabs, ['card/fixture/one']);
    expect(restored.active, 'card/fixture/one');
    expect(restored.section, 'passwords');
    expect(restored.rightCollapsed, isTrue);
    restored.close('card/fixture/one');
    expect(restored.tabs, isEmpty);
    expect(restored.active, isNull);
    tabs.dispose();
    restored.dispose();
  });
  test('malformed tabs fail before replacing a usable state', () {
    final tabs = WorkbenchTabs();
    tabs.open('agent');
    tabs.setRightCollapsed(true);
    final before = jsonEncode(tabs.toJson());
    expect(
      () => tabs.restore({
        'version': 2,
        'tabs': ['agent', 'agent'],
      }),
      throwsFormatException,
    );
    expect(
      () => tabs.restore({'version': 1, 'root': {'type': 'group'}}),
      throwsFormatException,
    );
    expect(jsonEncode(tabs.toJson()), before);
    expect(tabs.rightCollapsed, isTrue);
    tabs.dispose();
  });

  test('a record from before the right panel opens it by default', () {
    final tabs = WorkbenchTabs();
    tabs.setRightCollapsed(true);
    tabs.restore(
      jsonDecode(
        '{"version":2,"tabs":[],"active":null,"section":"inbox",'
        '"collapsed":false}',
      ) as Map<String, dynamic>,
    );
    expect(tabs.rightCollapsed, isFalse);
    tabs.dispose();
  });
  test(
    'shared edit buffers preserve drafts and edits made during a save',
    () async {
      final firstSave = Completer<void>();
      final saved = <CardDraft>[];
      final edits = CardEditSessions(
        canSave: () => true,
        debounce: const Duration(hours: 1),
        save: (_, draft) async {
          saved.add(draft);
          if (saved.length == 1) await firstSave.future;
        },
      );
      final session = edits.session(fixture());
      expect(edits.session(fixture()), same(session));
      edits.edit(session, content: '第一次修改');
      final flush = edits.flush();
      edits.edit(session, content: '保存期间继续修改');
      firstSave.complete();
      await flush;
      expect(session.state, CardSaveState.pending);
      await edits.flush();
      expect(saved.last.content, '保存期间继续修改');
      expect(saved.every((d) => d.status == CardStatus.draft), isTrue);
      expect(session.state, CardSaveState.saved);
      edits.dispose();
    },
  );
  test('failed save retains input for explicit retry', () async {
    var fail = true;
    final edits = CardEditSessions(
      canSave: () => true,
      debounce: const Duration(hours: 1),
      save: (_, draft) async {
        if (fail) throw const FormatException('存储失败');
      },
    );
    final session = edits.session(fixture());
    edits.edit(session, title: '未丢失');
    await edits.flush();
    expect(session.state, CardSaveState.failed);
    expect(session.title, '未丢失');
    fail = false;
    await edits.flush();
    expect(session.state, CardSaveState.saved);
    edits.dispose();
  });
}
