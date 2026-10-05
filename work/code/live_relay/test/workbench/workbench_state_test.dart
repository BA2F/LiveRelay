import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/workbench/card_edit_sessions.dart';
import 'package:live_relay/application/workbench/workbench_layout.dart';
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
      final a = await repo.createCard(const CardDraft(title: 'A', content: '来源 A'));
      final b = await repo.createCard(const CardDraft(title: 'B', content: '来源 B'));
      final links = CardReferenceStore(repo);
      await links.replace(a.id, [b.id, b.id]);
      expect((await links.read()).single.to, b.id);
      expect(await repo.relationsForCard(a.id), isEmpty);
      await expectLater(links.replace(a.id, [a.id]), throwsFormatException);
      await expectLater(links.replace(a.id, ['missing']), throwsFormatException);
      expect((await links.read()).single.to, b.id);
      await copy.importLocalState(await repo.exportLocalState());
      expect((await CardReferenceStore(copy).read()).single.from, a.id);
      await repo.trashCard(b.id); await repo.restoreCard(b.id);
      expect((await links.read()).single.to, b.id);
      expect((await repo.getReleasePolicy('card', a.id)).visibleAt(LifeState.deceased), VisibilityLevel.hidden);
    } finally { await repo.close(); await copy.close(); }
  });
  test('views survive split, merge, float and persisted reconstruction exactly once', () {
    final layout = WorkbenchLayout();
    final target = layout.groups.first.id;
    layout.move('agent', target, DockPlacement.bottom);
    expect(layout.root, isA<DockSplit>());
    layout.move('agent', '', DockPlacement.floating);
    expect(layout.floating.single.group.tabs, ['agent']);
    layout.open('card/fixture/one');
    layout.open('card/fixture/two');
    final restored = WorkbenchLayout();
    restored.restore(
      jsonDecode(jsonEncode(layout.toJson())) as Map<String, dynamic>,
    );
    expect(restored.floating.single.group.tabs, ['agent']);
    restored.move('agent', restored.groups.first.id, DockPlacement.center);
    expect(restored.floating, isEmpty);
    final tabs = restored.groups.expand((g) => g.tabs).toList();
    expect(tabs.toSet().length, tabs.length);
    expect(
      tabs,
      containsAll(['cards', 'agent', 'card/fixture/one', 'card/fixture/two']),
    );
    layout.dispose();
    restored.dispose();
  });
  test('malformed layout fails before replacing a usable tree', () {
    final layout = WorkbenchLayout();
    final before = jsonEncode(layout.toJson());
    expect(
      () => layout.restore({
        'version': 1,
        'root': {
          'type': 'group',
          'id': 'a',
          'tabs': ['cards', 'cards'],
        },
      }),
      throwsFormatException,
    );
    expect(jsonEncode(layout.toJson()), before);
    layout.dispose();
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
