import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/entities.dart';
import '../../core/domain/card_mutations.dart';
import '../../core/ai/review_source.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/reviewed_agent_plan.dart';
import '../../core/domain/card_references.dart';
import '../../core/domain/lifecycle.dart';
import '../../core/domain/vault_merge.dart';
import '../../core/ports/vault_repository.dart';
import 'app_database.dart';

class SqliteVaultRepository implements VaultRepository {
  SqliteVaultRepository(this.database, {Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? _utcNow;
  static DateTime _utcNow() => DateTime.now().toUtc();
  final DateTime Function() _clock;

  final AppDatabase database;
  final Uuid _uuid;
  final LifeStateMachine _stateMachine = const LifeStateMachine();

  DateTime get _now => _clock().toUtc();

  static const _stateTables = [
    'vault_local_state',
    'sources',
    'encrypted_blobs',
    'life_cards',
    'card_revisions',
    'card_relations',
    'credentials',
    'credential_revisions',
    'release_policies',
    'life_state_events',
    'audit_events',
  ];
  @override
  Future<String?> readLocalValue(String key) async => (await (database.select(
    database.vaultLocalState,
  )..where((t) => t.name.equals(key))).getSingleOrNull())?.value;
  @override
  Future<void> writeLocalValue(String key, String value) async {
    if (key.length > 100 || value.length > 1024 * 1024) {
      throw const FormatException('本地资料过大');
    }
    await database
        .into(database.vaultLocalState)
        .insertOnConflictUpdate(
          VaultLocalStateCompanion.insert(name: key, value: value),
        );
  }

  @override
  Future<void> writeLocalValues(Map<String, String> values) {
    final input = Map<String, String>.unmodifiable(values);
    return database.transaction(() async {
      for (final entry in input.entries) {
        await writeLocalValue(entry.key, entry.value);
      }
    });
  }

  @override
  Future<String?> readChunkedLocalValue(String key) =>
      database.transaction(() async {
        final raw = await readLocalValue(key);
        if (raw == null) return null;
        final data = jsonDecode(raw);
        if (data is! Map || data['chunked'] != 1) return raw;
        final count = data['count'];
        if (count is! int || count < 1 || count > 65) {
          throw const FormatException('会话分块无效');
        }
        final buffer = StringBuffer();
        for (var i = 0; i < count; i++) {
          final part = await readLocalValue('$key.part$i');
          if (part == null) throw const FormatException('会话分块缺失');
          buffer.write(part);
        }
        return buffer.toString();
      });
  @override
  Future<void> writeChunkedLocalValue(String key, String value) {
    if (key.length > 70 || value.length > 32 * 1024 * 1024) {
      throw const FormatException('会话过大，请开始新会话');
    }
    return database.transaction(() async {
      final old = await readLocalValue(key);
      final previous = old == null ? null : jsonDecode(old);
      final oldCount = previous is Map && previous['chunked'] == 1
          ? previous['count'] as int
          : 0;
      var count = 0;
      if (value.length <= 512 * 1024) {
        await writeLocalValue(key, value);
      } else {
        var start = 0;
        while (start < value.length) {
          var end = (start + 512 * 1024).clamp(0, value.length);
          if (end < value.length &&
              value.codeUnitAt(end - 1) >= 0xd800 &&
              value.codeUnitAt(end - 1) <= 0xdbff) {
            end--;
          }
          await writeLocalValue('$key.part$count', value.substring(start, end));
          count++;
          start = end;
        }
        await writeLocalValue(key, jsonEncode({'chunked': 1, 'count': count}));
      }
      for (var i = count; i < oldCount; i++) {
        await (database.delete(
          database.vaultLocalState,
        )..where((t) => t.name.equals('$key.part$i'))).go();
      }
    });
  }

  @override
  Future<Uint8List> exportLocalState() => database.transaction(() async {
    final state = <String, Object?>{};
    for (final table in _stateTables) {
      state[table] =
          (await database.customSelect('SELECT * FROM "$table"').get())
              .map((r) => r.data)
              .toList();
    }
    return Uint8List.fromList(utf8.encode(jsonEncode(state)));
  });
  @override
  Future<void> importLocalState(Uint8List bytes) async {
    if (bytes.length > 256 * 1024 * 1024) {
      throw const FormatException('数据库快照过大');
    }
    final state = jsonDecode(utf8.decode(bytes));
    if (state is! Map ||
        state.length != _stateTables.length ||
        !_stateTables.every(state.containsKey)) {
      throw const FormatException('数据库快照结构错误');
    }
    await database.customStatement('PRAGMA foreign_keys = OFF');
    try {
      await database.transaction(() async {
        for (final table in _stateTables) {
          await database.customStatement('DELETE FROM "$table"');
          final columns =
              (await database.customSelect('PRAGMA table_info("$table")').get())
                  .map((r) => r.data['name'] as String)
                  .toSet();
          final rows = state[table];
          if (rows is! List) throw const FormatException('数据库表结构错误');
          for (final raw in rows) {
            if (raw is! Map ||
                raw.length != columns.length ||
                !columns.containsAll(raw.keys.cast<String>())) {
              throw const FormatException('数据库列结构错误');
            }
            final names = raw.keys.cast<String>().toList();
            await database.customStatement(
              'INSERT INTO "$table" (${names.map((n) => '"$n"').join(',')}) VALUES (${names.map((_) => '?').join(',')})',
              names.map((n) => raw[n]).toList(),
            );
          }
        }
        if ((await database.customSelect('PRAGMA foreign_key_check').get())
            .isNotEmpty) {
          throw const FormatException('数据库关联不完整');
        }
      });
    } finally {
      await database.customStatement('PRAGMA foreign_keys = ON');
    }
  }

  @override
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
    bool recycled = false,
  }) async {
    final statement = database.select(database.cards)
      ..where(
        (table) =>
            recycled ? table.deletedAt.isNotNull() : table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.updatedAt),
        (_) => OrderingTerm(
          expression: const CustomExpression<int>(
            "(SELECT MAX(id) FROM audit_events WHERE entity_type='card' AND entity_id=life_cards.id)",
          ),
          mode: OrderingMode.desc,
        ),
      ]);
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (table) =>
            table.title.like(pattern) |
            table.content.like(pattern) |
            table.tagsJson.like(pattern),
      );
    }
    if (kind != null) {
      statement.where((table) => table.kind.equals(kind.name));
    }
    if (status != null) {
      statement.where((table) => table.status.equals(status.name));
    }
    return (await statement.get()).map(_cardFromRow).toList(growable: false);
  }

  @override
  Future<LifeCard?> getCard(String id) async {
    final row = await (database.select(
      database.cards,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _cardFromRow(row);
  }

  static const _referencesKey = 'workbench.references.v1';
  @override
  Future<List<CardReference>> cardReferences() async {
    final raw = await readLocalValue(_referencesKey);
    if (raw == null) return [];
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('引用版本不支持');
    return List.unmodifiable([
      for (final r in data['references'] as List)
        CardReference(r['from'] as String, r['to'] as String),
    ]);
  }

  @override
  Future<void> setCardReferences(String from, List<String> input) async {
    final targets = CardReferenceRules.targets(from, List.of(input));
    return database.transaction(() async {
      final facts = <String, LifeCard?>{};
      for (final id in [from, ...targets]) {
        facts[id] = await getCard(id);
      }
      CardReferenceRules.validate(from, targets, facts);
      final next = CardReferenceRules.replace(
        await cardReferences(),
        from,
        targets,
      );
      await writeLocalValue(
        _referencesKey,
        jsonEncode({
          'version': 1,
          'references': [
            for (final r in next) {'from': r.from, 'to': r.to},
          ],
        }),
      );
    });
  }

  @override
  Future<List<CardRevision>> cardHistory(String cardId) async {
    final rows =
        await (database.select(database.cardRevisions)
              ..where((table) => table.cardId.equals(cardId))
              ..orderBy([(table) => OrderingTerm.desc(table.number)]))
            .get();
    return rows.map(_cardRevisionFromRow).toList(growable: false);
  }

  @override
  Future<LifeCard> createCard(
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String sourceLabel = '本人输入',
  }) {
    return database.transaction(
      () =>
          _insertCard(draft, sourceKind: sourceKind, sourceLabel: sourceLabel),
    );
  }

  Future<LifeCard> _insertCard(
    CardDraft draft, {
    required SourceKind sourceKind,
    required String sourceLabel,
    String? parentCardId,
    String? blobId,
    String? sourceText,
  }) async {
    DraftRules.validateCard(draft);
    final id = _uuid.v7();
    final sourceId = _uuid.v7();
    final now = _now;
    final tags = DraftRules.normalizedTags(draft.tags);
    await database
        .into(database.sources)
        .insert(
          SourcesCompanion.insert(
            id: sourceId,
            kind: sourceKind.name,
            label: sourceLabel,
            textExcerpt: Value(sourceText ?? draft.content),
            blobId: Value(blobId),
            createdAt: now,
          ),
        );
    await database
        .into(database.cards)
        .insert(
          CardsCompanion.insert(
            id: id,
            title: draft.title.trim(),
            content: draft.content.trim(),
            kind: draft.kind.name,
            status: draft.status.name,
            tagsJson: Value(jsonEncode(tags)),
            createdAt: now,
            updatedAt: now,
            confirmedAt: Value(
              draft.status == CardStatus.confirmed ? now : null,
            ),
            parentCardId: Value(parentCardId),
          ),
        );
    await _insertCardRevision(
      cardId: id,
      number: 1,
      draft: CardDraft(
        title: draft.title.trim(),
        content: draft.content.trim(),
        kind: draft.kind,
        status: draft.status,
        tags: tags,
      ),
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
      sourceId: sourceId,
      changeNote: draft.status == CardStatus.draft ? '保存草稿' : '创建卡片',
      createdAt: now,
    );
    await _audit('create', 'card', id, '创建${draft.status.name}卡片');
    return (await getCard(id))!;
  }

  @override
  Future<LifeCard> updateCard(
    String id,
    CardDraft draft, {
    String changeNote = '更新卡片',
  }) {
    return database.transaction(() async {
      DraftRules.validateCard(draft);
      final existing = await getCard(id);
      if (existing == null || existing.isDeleted) {
        throw StateError('卡片不存在');
      }
      final now = _now;
      final revision = existing.revisionNumber + 1;
      final tags = DraftRules.normalizedTags(draft.tags);
      await (database.update(
        database.cards,
      )..where((table) => table.id.equals(id))).write(
        CardsCompanion(
          title: Value(draft.title.trim()),
          content: Value(draft.content.trim()),
          kind: Value(draft.kind.name),
          status: Value(draft.status.name),
          tagsJson: Value(jsonEncode(tags)),
          updatedAt: Value(now),
          confirmedAt: Value(draft.status == CardStatus.confirmed ? now : null),
          revisionNumber: Value(revision),
        ),
      );
      await _insertCardRevision(
        cardId: id,
        number: revision,
        draft: CardDraft(
          title: draft.title.trim(),
          content: draft.content.trim(),
          kind: draft.kind,
          status: draft.status,
          tags: tags,
        ),
        sourceKind: SourceKind.ownerInput,
        sourceLabel: '本人修改',
        changeNote: changeNote,
        createdAt: now,
      );
      await _audit('update', 'card', id, changeNote);
      return (await getCard(id))!;
    });
  }

  @override
  Future<LifeCard> confirmCard(String id) => database.transaction(() async {
    final card = await getCard(id);
    if (card == null || card.isDeleted) throw StateError('卡片不存在');
    if (card.status == CardStatus.confirmed) return card;
    return updateCard(
      id,
      CardDraft(
        title: card.title,
        content: card.content,
        kind: card.kind,
        status: CardStatus.confirmed,
        tags: card.tags,
      ),
      changeNote: '本人确认草稿',
    );
  });

  @override
  Future<List<LifeCard>> splitCard(String id, List<CardDraft> parts) {
    final requested = List<CardDraft>.unmodifiable(
      parts.map(DraftRules.freeze),
    );
    if (requested.length < 2) throw const FormatException('拆分至少需要两张卡片');
    return database.transaction(() async {
      final original = await getCard(id);
      final plan = SplitCardPlan(original, requested);
      final now = _now;
      final revision = plan.revision;
      await (database.update(
        database.cards,
      )..where((table) => table.id.equals(id))).write(
        CardsCompanion(
          status: Value(CardStatus.split.name),
          updatedAt: Value(now),
          revisionNumber: Value(revision),
        ),
      );
      await _insertCardRevision(
        cardId: id,
        number: revision,
        draft: plan.parent,
        sourceKind: SourceKind.ownerInput,
        sourceLabel: '本人整理',
        changeNote: plan.revisionNote,
        createdAt: now,
      );
      final children = <LifeCard>[];
      for (final part in plan.parts) {
        final child = await _insertCard(
          part,
          sourceKind: SourceKind.ownerInput,
          sourceLabel: plan.childSourceLabel,
          parentCardId: id,
        );
        children.add(child);
        await database
            .into(database.cardRelations)
            .insert(
              CardRelationsCompanion.insert(
                fromCardId: child.id,
                toCardId: id,
                kind: RelationKind.splitFrom.name,
                createdAt: now,
              ),
            );
      }
      await _audit('split', 'card', id, '拆分为 ${parts.length} 张卡片');
      return children;
    });
  }

  @override
  Future<LifeCard> combineCards(String title, List<String> memberIds) {
    final plan = BundleCardPlan(title, memberIds);
    return database.transaction(() async {
      final facts = <String, LifeCard?>{};
      for (final id in plan.memberIds) {
        facts[id] = await getCard(id);
      }
      plan.validateMembers(facts);
      final bundle = await _insertCard(
        plan.draft,
        sourceKind: SourceKind.ownerInput,
        sourceLabel: '本人组合',
      );
      final now = _now;
      for (final memberId in plan.memberIds) {
        await database
            .into(database.cardRelations)
            .insert(
              CardRelationsCompanion.insert(
                fromCardId: bundle.id,
                toCardId: memberId,
                kind: RelationKind.bundleMember.name,
                createdAt: now,
              ),
            );
      }
      await _audit('combine', 'card', bundle.id, '组合 ${memberIds.length} 张卡片');
      return bundle;
    });
  }

  @override
  Future<List<CardRelation>> relationsForCard(String cardId) async {
    final rows =
        await (database.select(database.cardRelations)..where(
              (table) =>
                  table.fromCardId.equals(cardId) |
                  table.toCardId.equals(cardId),
            ))
            .get();
    return rows
        .map(
          (row) => CardRelation(
            fromCardId: row.fromCardId,
            toCardId: row.toCardId,
            kind: RelationKind.values.byName(row.kind),
          ),
        )
        .toList(growable: false);
  }

  static const _originalTrashKey = 'workbench.original-trash.v1';
  String _bindingKey(String id) => 'card.originals.$id';
  Future<Map<String, dynamic>?> _binding(String id) async {
    final raw = await readLocalValue(_bindingKey(id));
    if (raw == null) return null;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('来源引用版本不支持');
    return data;
  }

  Future<List<String>> _historicalOriginals(String id, {int? number}) async {
    final rows = await database
        .customSelect(
          'SELECT DISTINCT s.blob_id FROM sources s JOIN card_revisions r ON r.source_id=s.id '
          'WHERE r.card_id=? AND s.blob_id IS NOT NULL AND r.number<=?',
          variables: [
            Variable<String>(id),
            Variable<int>(number ?? 2147483647),
          ],
          readsFrom: {database.sources, database.cardRevisions},
        )
        .get();
    return rows.map((r) => r.read<String>('blob_id')).toList();
  }

  @override
  Future<List<CardSource>> currentCardSources(String id) async {
    final binding = await _binding(id);
    final all = await cardSources(id);
    if (binding == null) return all;
    final active = (binding['current'] as List).cast<String>().toSet();
    return all
        .where((s) => s.blobId == null || active.contains(s.blobId))
        .toList();
  }

  @override
  Future<void> setCardOriginals(
    String id,
    List<String> blobIds,
  ) => database.transaction(() async {
    final card = await getCard(id);
    if (card == null || card.isDeleted) throw const FormatException('卡片不存在');
    final selected = blobIds.toSet();
    if (selected.length > 100) throw const FormatException('单卡最多引用100个原件');
    final blobs = {for (final b in await listBlobs()) b.id: b};
    if (selected.any((id) => !blobs.containsKey(id))) {
      throw const FormatException('来源原件不存在');
    }
    final historical = await _historicalOriginals(id);
    final binding =
        await _binding(id) ??
        {'version': 1, 'current': historical, 'revisions': <String, dynamic>{}};
    final before = (binding['current'] as List).cast<String>().toSet();
    if (before.length == selected.length && before.containsAll(selected)) {
      return;
    }
    final snapshots = Map<String, dynamic>.from(binding['revisions'] as Map);
    snapshots['${card.revisionNumber}'] = before.toList();
    binding['current'] = selected.toList();
    binding['revisions'] = snapshots;
    await writeLocalValue(_bindingKey(id), jsonEncode(binding));
    final added = selected.difference(historical.toSet());
    for (final blobId in added) {
      final sourceId = _uuid.v7();
      final blob = blobs[blobId]!;
      await database
          .into(database.sources)
          .insert(
            SourcesCompanion.insert(
              id: sourceId,
              kind: SourceKind.ownerInput.name,
              label: '本人引用 · ${blob.originalName}',
              blobId: Value(blobId),
              createdAt: _now,
            ),
          );
      final updated = await updateCard(
        id,
        CardDraft(
          title: card.title,
          content: card.content,
          kind: card.kind,
          status: card.status,
          tags: card.tags,
        ),
        changeNote: '添加原件引用 · ${blob.originalName}',
      );
      await (database.update(database.cardRevisions)..where(
            (r) =>
                r.cardId.equals(id) & r.number.equals(updated.revisionNumber),
          ))
          .write(
            CardRevisionsCompanion(
              sourceId: Value(sourceId),
              sourceLabel: Value('本人引用 · ${blob.originalName}'),
            ),
          );
    }
    if (added.isEmpty) {
      await updateCard(
        id,
        CardDraft(
          title: card.title,
          content: card.content,
          kind: card.kind,
          status: card.status,
          tags: card.tags,
        ),
        changeNote: '调整原件引用（历史保留）',
      );
    }
    final trash = (await recycledOriginalIds()).toSet()..removeAll(selected);
    await writeLocalValue(
      _originalTrashKey,
      jsonEncode({'version': 1, 'ids': trash.toList()}),
    );
    await _audit('sources', 'card', id, '引用${selected.length}个原件；历史来源保留');
  });
  @override
  Future<LifeCard> restoreCardRevision(
    String id,
    int number,
  ) => database.transaction(() async {
    final card = await getCard(id);
    if (card == null || card.isDeleted) throw const FormatException('卡片不存在');
    final revision = (await cardHistory(id))
        .where((r) => r.number == number)
        .firstOrNull;
    if (revision == null) throw const FormatException('修订不存在');
    final binding =
        await _binding(id) ??
        {
          'version': 1,
          'current': await _historicalOriginals(id),
          'revisions': <String, dynamic>{},
        };
    final snapshots = Map<String, dynamic>.from(binding['revisions'] as Map);
    snapshots['${card.revisionNumber}'] = binding['current'];
    final originals =
        snapshots['$number'] ?? await _historicalOriginals(id, number: number);
    binding['current'] = originals;
    binding['revisions'] = snapshots;
    await writeLocalValue(_bindingKey(id), jsonEncode(binding));
    final trash = (await recycledOriginalIds()).toSet()
      ..removeAll((originals as List).cast<String>());
    await writeLocalValue(
      _originalTrashKey,
      jsonEncode({'version': 1, 'ids': trash.toList()}),
    );
    return updateCard(
      id,
      CardDraft(
        title: revision.title,
        content: revision.content,
        kind: card.kind,
        status: card.status,
        tags: revision.tags,
      ),
      changeNote: '恢复修订 $number 为新修订',
    );
  });
  @override
  Future<List<String>> recycledOriginalIds() async {
    final raw = await readLocalValue(_originalTrashKey);
    if (raw == null) return [];
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('原件回收版本不支持');
    return (data['ids'] as List).cast<String>();
  }

  @override
  Future<void> restoreOriginal(String id) => database.transaction(() async {
    if (!(await listBlobs()).any((b) => b.id == id)) {
      throw const FormatException('原件不存在');
    }
    final ids = (await recycledOriginalIds()).toSet()..remove(id);
    await writeLocalValue(
      _originalTrashKey,
      jsonEncode({'version': 1, 'ids': ids.toList()}),
    );
    await _audit('restore', 'blob', id, '恢复原件');
  });
  @override
  Future<CardDeletionPreview> previewCardDeletion(List<String> ids) async {
    final selected = ids.toSet();
    if (selected.isEmpty || selected.length != ids.length) {
      throw const FormatException('请选择不同的卡片');
    }
    final candidates = <String>{};
    for (final id in selected) {
      final card = await getCard(id);
      if (card == null || card.isDeleted) throw const FormatException('卡片不存在');
      candidates.addAll(await _historicalOriginals(id));
    }
    final eligible = <String>{}, protected = <String>{};
    for (final blobId in candidates) {
      // Include other cards' history AND recycled cards. No physical blob is
      // destroyed, and an existing recovery path never loses its original.
      final refs = await database
          .customSelect(
            'SELECT DISTINCT r.card_id FROM card_revisions r JOIN sources s ON r.source_id=s.id WHERE s.blob_id=?',
            variables: [Variable<String>(blobId)],
            readsFrom: {database.cardRevisions, database.sources},
          )
          .get();
      if (refs.any((r) => !selected.contains(r.read<String>('card_id')))) {
        protected.add(blobId);
      } else {
        eligible.add(blobId);
      }
    }
    final blobs = await listBlobs();
    return CardDeletionPreview(
      recyclableOriginals: blobs.where((b) => eligible.contains(b.id)).toList(),
      protectedOriginals: blobs.where((b) => protected.contains(b.id)).toList(),
    );
  }

  @override
  Future<void> trashCards(
    List<String> ids, {
    bool recycleUnsharedOriginals = false,
  }) => database.transaction(() async {
    final preview = await previewCardDeletion(ids);
    for (final id in ids) {
      await trashCard(id);
    }
    if (recycleUnsharedOriginals) {
      final recycled = (await recycledOriginalIds()).toSet()
        ..addAll(preview.recyclableOriginals.map((b) => b.id));
      await writeLocalValue(
        _originalTrashKey,
        jsonEncode({'version': 1, 'ids': recycled.toList()}),
      );
      for (final blob in preview.recyclableOriginals) {
        await _audit('trash', 'blob', blob.id, '随未共享卡片移入回收区，保留历史恢复');
      }
    }
  });

  @override
  Future<void> trashCard(String id) async {
    final changed =
        await (database.update(
          database.cards,
        )..where((table) => table.id.equals(id))).write(
          CardsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
        );
    if (changed == 0) throw StateError('卡片不存在');
    await _audit('trash', 'card', id, '移入回收区，历史仍保留');
  }

  @override
  Future<void> restoreCard(String id) => database.transaction(() async {
    final changed =
        await (database.update(
          database.cards,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNotNull())).write(
          CardsCompanion(deletedAt: const Value(null), updatedAt: Value(_now)),
        );
    if (changed == 0) throw StateError('回收区中没有这张卡片');
    final originals = await _historicalOriginals(id);
    final recycled = (await recycledOriginalIds()).toSet()
      ..removeAll(originals);
    await writeLocalValue(
      _originalTrashKey,
      jsonEncode({'version': 1, 'ids': recycled.toList()}),
    );
    await _audit('restore', 'card', id, '恢复卡片，保留内容、来源、历史和已有授权');
  });

  @override
  Future<List<CardSource>> cardSources(String id) async {
    final rows =
        await (database.select(database.cardRevisions)
              ..where((t) => t.cardId.equals(id))
              ..orderBy([(t) => OrderingTerm.desc(t.number)]))
            .get();
    final result = <CardSource>[];
    final seen = <String>{};
    for (final revision in rows) {
      final source = revision.sourceId == null
          ? null
          : await (database.select(
              database.sources,
            )..where((t) => t.id.equals(revision.sourceId!))).getSingleOrNull();
      if (!seen.add(source?.id ?? 'revision-${revision.id}')) continue;
      result.add(
        CardSource(
          label: source?.label ?? revision.sourceLabel,
          kind: SourceKind.values.byName(source?.kind ?? revision.sourceKind),
          excerpt: source?.textExcerpt ?? revision.content,
          createdAt: source?.createdAt ?? revision.createdAt,
          blobId: source?.blobId,
        ),
      );
    }
    return result;
  }

  @override
  Future<List<LifeCard>> cardsForBlob(String blobId) async {
    final rows = await database
        .customSelect(
          'SELECT DISTINCT life_cards.* FROM life_cards '
          'JOIN card_revisions ON card_revisions.card_id = life_cards.id '
          'JOIN sources ON sources.id = card_revisions.source_id '
          'WHERE sources.blob_id = ? AND life_cards.deleted_at IS NULL '
          'ORDER BY life_cards.updated_at DESC',
          variables: [Variable<String>(blobId)],
          readsFrom: {database.cards, database.cardRevisions, database.sources},
        )
        .get();
    return rows
        .map((row) => _cardFromRow(database.cards.map(row.data)))
        .toList();
  }

  @override
  Future<LifeCard> createCardFromOriginal(
    String blobId,
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String? sourceLabel,
  }) => database.transaction(() async {
    final blob = await (database.select(
      database.encryptedBlobs,
    )..where((t) => t.id.equals(blobId))).getSingleOrNull();
    if (blob == null) throw StateError('原件不存在');
    return _insertCard(
      draft,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel ?? '本人整理 · ${blob.originalName}',
      blobId: blobId,
    );
  });

  @override
  Future<DateTime?> lastBackupExport() async {
    final row =
        await (database.select(database.auditEvents)
              ..where((t) => t.action.equals('backup-export'))
              ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)])
              ..limit(1))
            .getSingleOrNull();
    return row?.occurredAt;
  }

  @override
  Future<void> recordBackupExport(DateTime time) async {
    await database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            action: 'backup-export',
            entityType: 'vault',
            entityId: 'local',
            description: '文件选择器报告加密备份导出成功；设备外副本未核验',
            occurredAt: time.toUtc(),
          ),
        );
  }

  @override
  Future<List<VaultBlob>> listBlobs() async {
    final rows = await (database.select(
      database.encryptedBlobs,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();
    return rows.map(_blobFromRow).toList(growable: false);
  }

  @override
  Future<VaultBlob?> getBlob(String id) async {
    final row = await (database.select(
      database.encryptedBlobs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _blobFromRow(row);
  }

  @override
  Future<void> registerBlobRow(VaultBlob blob) {
    return database.transaction(() async {
      await database
          .into(database.encryptedBlobs)
          .insert(
            EncryptedBlobsCompanion.insert(
              id: blob.id,
              originalName: blob.originalName,
              mediaKind: blob.mediaKind.name,
              mimeType: blob.mimeType,
              relativePath: blob.relativePath,
              byteLength: blob.byteLength,
              sha256: blob.sha256,
              ocrText: Value(blob.ocrText),
              ocrJson: Value(
                blob.ocrLines.isEmpty ? null : _encodeOcrLines(blob.ocrLines),
              ),
              sensitiveJson: Value(
                blob.sensitiveMarks.isEmpty
                    ? null
                    : _encodeSensitiveMarks(blob.sensitiveMarks),
              ),
              createdAt: blob.createdAt,
            ),
          );
      await _audit('import', 'blob', blob.id, '加密保存原始资料');
    });
  }

  @override
  Future<LifeCard> registerBlob(VaultBlob blob) {
    return database.transaction(() async {
      await registerBlobRow(blob);
      final sourceKind = switch (blob.mediaKind) {
        BlobMediaKind.image => SourceKind.photo,
        BlobMediaKind.audio => SourceKind.audio,
        BlobMediaKind.video => SourceKind.video,
        BlobMediaKind.document || BlobMediaKind.other => SourceKind.imported,
      };
      final label = switch (blob.mediaKind) {
        BlobMediaKind.image => '加密照片原件',
        BlobMediaKind.audio => '加密录音原件',
        BlobMediaKind.video => '加密录像原件',
        BlobMediaKind.document => '加密文档原件',
        BlobMediaKind.other => '加密原始资料',
      };
      final card = await _insertCard(
        CardDraft(
          title: blob.originalName,
          content:
              '$label\n${blob.mimeType} · ${_readableByteLength(blob.byteLength)}',
          kind: CardKind.document,
          tags: [blob.mediaKind.name, '原始资料'],
        ),
        sourceKind: sourceKind,
        sourceLabel: label,
        blobId: blob.id,
      );
      await _audit('import', 'blob', blob.id, '创建来源卡片：${blob.originalName}');
      return card;
    });
  }

  @override
  Future<void> updateBlobOcr(String id, String text) async {
    final changed =
        await (database.update(database.encryptedBlobs)
              ..where((table) => table.id.equals(id)))
            .write(EncryptedBlobsCompanion(ocrText: Value(text.trim())));
    if (changed == 0) throw StateError('原始资料不存在');
    await _audit('ocr', 'blob', id, '保存本地 OCR 文本');
  }

  @override
  Future<LifeCard> saveOcrResult(String blobId, OcrResult result) {
    return database.transaction(() async {
      if (result.text.trim().isEmpty) {
        throw const FormatException('图片中没有识别到文字');
      }
      final row = await (database.select(
        database.encryptedBlobs,
      )..where((table) => table.id.equals(blobId))).getSingleOrNull();
      if (row == null) throw StateError('原始资料不存在');
      if (row.mediaKind != BlobMediaKind.image.name) {
        throw const FormatException('只有图片原件可以执行 OCR');
      }
      await (database.update(
        database.encryptedBlobs,
      )..where((table) => table.id.equals(blobId))).write(
        EncryptedBlobsCompanion(
          ocrText: Value(result.text.trim()),
          ocrJson: Value(_encodeOcrLines(result.lines)),
        ),
      );
      final card = await _insertCard(
        CardDraft(
          title: 'OCR：${row.originalName}',
          content: result.text.trim(),
          kind: CardKind.document,
          status: CardStatus.draft,
          tags: const ['OCR', '待确认'],
        ),
        sourceKind: SourceKind.ocrDerived,
        sourceLabel: '本地 OCR · ${row.originalName}',
        blobId: blobId,
      );
      await _audit('ocr', 'blob', blobId, '本地 OCR 生成待确认草稿');
      return card;
    });
  }

  @override
  Future<void> saveSensitiveMarks(
    String blobId,
    List<SensitiveMark> marks,
  ) async {
    final uniqueOrders = marks.map((mark) => mark.lineOrder).toSet();
    if (uniqueOrders.length != marks.length) {
      throw const FormatException('同一 OCR 文本行只能标记一种敏感类型');
    }
    final changed =
        await (database.update(
          database.encryptedBlobs,
        )..where((table) => table.id.equals(blobId))).write(
          EncryptedBlobsCompanion(
            sensitiveJson: Value(_encodeSensitiveMarks(marks)),
          ),
        );
    if (changed == 0) throw StateError('原始资料不存在');
    await _audit(
      'mark-sensitive',
      'blob',
      blobId,
      '保存 ${marks.length} 个人工敏感标记',
    );
  }

  @override
  Future<List<LifeCard>> saveAiSuggestions(
    String blobId,
    List<CardDraft> drafts, {
    required String providerLabel,
  }) {
    return database.transaction(() async {
      final blobExists =
          await (database.selectOnly(database.encryptedBlobs)
                ..addColumns([database.encryptedBlobs.id])
                ..where(database.encryptedBlobs.id.equals(blobId)))
              .getSingleOrNull();
      if (blobExists == null) throw StateError('原始资料不存在');
      if (drafts.isEmpty || drafts.length > 20) {
        throw const FormatException('AI 草稿数量异常');
      }
      final cards = <LifeCard>[];
      for (final draft in drafts) {
        cards.add(
          await _insertCard(
            CardDraft(
              title: draft.title,
              content: draft.content,
              kind: draft.kind,
              tags: draft.tags,
              status: CardStatus.draft,
            ),
            sourceKind: SourceKind.aiGenerated,
            sourceLabel: providerLabel,
            blobId: blobId,
          ),
        );
      }
      await _audit(
        'ai-organize',
        'blob',
        blobId,
        '获授权云 AI 生成 ${cards.length} 张待确认草稿',
      );
      return cards;
    });
  }

  @override
  Future<List<LifeCard>> saveAgentSuggestions(
    String sourceText,
    List<CardDraft> drafts, {
    required String providerLabel,
  }) {
    if (sourceText.length > 32000 || drafts.isEmpty || drafts.length > 20) {
      throw const FormatException('Agent 草稿数量或来源大小错误');
    }
    return database.transaction(() async {
      final cards = <LifeCard>[];
      for (final draft in drafts) {
        cards.add(
          await _insertCard(
            CardDraft(
              title: draft.title,
              content: draft.content,
              kind: draft.kind,
              status: CardStatus.draft,
              tags: draft.tags,
            ),
            sourceKind: SourceKind.aiGenerated,
            sourceLabel: providerLabel,
            sourceText: sourceText,
          ),
        );
      }
      await _audit(
        'agent-organize',
        'cards',
        '',
        '本人核对并保存 ${cards.length} 张 Agent 草稿',
      );
      return cards;
    });
  }

  @override
  Future<List<LifeCard>> saveReviewedAgentSuggestions(
    String reviewId,
    String sourceText,
    List<CardDraft> drafts, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  }) {
    final reviewed = ReviewedAgentPlan(
      reviewId: reviewId,
      sourceText: sourceText,
      drafts: drafts,
      providerLabel: providerLabel,
      reviewSource: reviewSource,
      actions: actions,
    );
    final retainedOriginalIds = List<String>.unmodifiable(originalIds);
    return database.transaction(() async {
      final receiptKey = reviewed.receiptKey;
      final receipt = await readLocalValue(receiptKey);
      if (receipt != null) {
        final cards = <LifeCard>[];
        for (final id in jsonDecode(receipt) as List) {
          final card = await getCard(id as String);
          if (card != null) cards.add(card);
        }
        return cards;
      }
      final targets = <String, LifeCard?>{};
      for (final id in reviewed.targetIds) {
        targets[id] = await getCard(id);
      }
      reviewed.validateTargets(targets);
      final cards = <LifeCard>[];
      for (final draft in reviewed.drafts) {
        cards.add(
          await _insertCard(
            CardDraft(
              title: draft.title,
              content: draft.content,
              kind: draft.kind,
              status: CardStatus.confirmed,
              tags: draft.tags,
            ),
            sourceKind: SourceKind.aiGenerated,
            sourceLabel: providerLabel,
            sourceText: reviewed.legacySource,
          ),
        );
      }
      if (retainedOriginalIds.isNotEmpty) {
        for (var i = 0; i < cards.length; i++) {
          await setCardOriginals(cards[i].id, retainedOriginalIds);
          cards[i] = (await getCard(cards[i].id))!;
        }
      }
      for (var i = 0; i < reviewed.actions.length; i++) {
        final plan = reviewed.actions[i], card = cards[i];
        if (plan.referenceIds.isNotEmpty) {
          await setCardReferences(card.id, plan.referenceIds);
        }
        if (plan.bundleId != null) {
          await database
              .into(database.cardRelations)
              .insert(
                CardRelationsCompanion.insert(
                  fromCardId: plan.bundleId!,
                  toCardId: card.id,
                  kind: RelationKind.bundleMember.name,
                  createdAt: _now,
                ),
              );
        }
        if (plan.incapacitated != VisibilityLevel.hidden ||
            plan.deceased != VisibilityLevel.hidden) {
          await saveReleasePolicy(
            ReleasePolicy(
              recordType: 'card',
              recordId: card.id,
              incapacitated: plan.incapacitated,
              deceased: plan.deceased,
            ),
          );
        }
      }
      if (reviewSource != null) {
        await writeChunkedLocalValue(
          reviewSource.storageKey,
          reviewed.evidence!,
        );
        for (final card in cards) {
          await writeLocalValue(
            ReviewSource.cardKey(card.id),
            reviewSource.storageKey,
          );
        }
      }
      await writeLocalValue(
        reviewed.planKey,
        jsonEncode({
          'version': 1,
          'actions': [for (final plan in reviewed.actions) plan.toJson()],
        }),
      );
      await writeLocalValue(
        receiptKey,
        jsonEncode(cards.map((c) => c.id).toList()),
      );
      await _audit(
        'agent-review',
        'cards',
        reviewId,
        '本人编辑并明确确认 ${cards.length} 张建议',
      );
      return cards;
    });
  }

  @override
  Future<ReviewSource?> cardReviewSource(String cardId) =>
      database.transaction(() async {
        if (await getCard(cardId) == null) return null;
        final key = await readLocalValue(ReviewSource.cardKey(cardId));
        if (key == null) return null;
        if (!RegExp(r'^ars\.[a-zA-Z0-9-]{1,64}$').hasMatch(key)) {
          throw const FormatException('确认来源链接无效');
        }
        final value = await readChunkedLocalValue(key);
        if (value == null) throw const FormatException('确认来源记录缺失');
        final source = ReviewSource.decode(value);
        if (source.storageKey != key) {
          source.wipe();
          throw const FormatException('确认来源链接不匹配');
        }
        return source;
      });

  @override
  Future<List<CredentialEntry>> listCredentials({
    String query = '',
    bool recycled = false,
  }) async {
    final statement = database.select(database.credentials)
      ..where(
        (table) =>
            recycled ? table.deletedAt.isNotNull() : table.deletedAt.isNull(),
      )
      ..orderBy([
        (table) => OrderingTerm.desc(table.updatedAt),
        (_) => OrderingTerm(
          expression: const CustomExpression<int>(
            "(SELECT MAX(id) FROM audit_events WHERE entity_type='credential' AND entity_id=credentials.id)",
          ),
          mode: OrderingMode.desc,
        ),
      ]);
    if (query.trim().isNotEmpty) {
      final pattern = '%${query.trim()}%';
      statement.where(
        (table) =>
            table.title.like(pattern) |
            table.username.like(pattern) |
            table.website.like(pattern) |
            table.notes.like(pattern) |
            table.tagsJson.like(pattern),
      );
    }
    return (await statement.get())
        .map(_credentialFromRow)
        .toList(growable: false);
  }

  @override
  Future<CredentialEntry> saveCredential(CredentialDraft draft, {String? id}) {
    return database.transaction(() async {
      DraftRules.validateCredential(draft);
      final now = _now;
      final tags = DraftRules.normalizedTags(draft.tags);
      if (id == null) {
        final newId = _uuid.v7();
        await database
            .into(database.credentials)
            .insert(
              CredentialsCompanion.insert(
                id: newId,
                title: draft.title.trim(),
                username: draft.username.trim(),
                secret: draft.secret,
                website: Value(draft.website.trim()),
                notes: Value(draft.notes.trim()),
                tagsJson: Value(jsonEncode(tags)),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _insertCredentialRevision(newId, 1, draft, '创建密码条目', now);
        await _audit('create', 'credential', newId, '创建密码条目');
        return (await _credentialById(newId))!;
      }

      final existing = await _credentialById(id);
      if (existing == null || existing.isDeleted) throw StateError('密码条目不存在');
      final revision = existing.revisionNumber + 1;
      await (database.update(
        database.credentials,
      )..where((table) => table.id.equals(id))).write(
        CredentialsCompanion(
          title: Value(draft.title.trim()),
          username: Value(draft.username.trim()),
          secret: Value(draft.secret),
          website: Value(draft.website.trim()),
          notes: Value(draft.notes.trim()),
          tagsJson: Value(jsonEncode(tags)),
          updatedAt: Value(now),
          revisionNumber: Value(revision),
        ),
      );
      await _insertCredentialRevision(id, revision, draft, '更新密码条目', now);
      await _audit('update', 'credential', id, '更新密码条目并保留旧 Secret');
      return (await _credentialById(id))!;
    });
  }

  @override
  Future<int> importCredentials(List<CredentialDraft> drafts) {
    return database.transaction(() async {
      final now = _now;
      for (final draft in drafts) {
        DraftRules.validateCredential(draft);
        final id = _uuid.v7();
        await database
            .into(database.credentials)
            .insert(
              CredentialsCompanion.insert(
                id: id,
                title: draft.title.trim(),
                username: draft.username.trim(),
                secret: draft.secret,
                website: Value(draft.website.trim()),
                notes: Value(draft.notes.trim()),
                tagsJson: Value(
                  jsonEncode(DraftRules.normalizedTags(draft.tags)),
                ),
                createdAt: now,
                updatedAt: now,
              ),
            );
        await _insertCredentialRevision(id, 1, draft, '从 Edge CSV 导入', now);
        await _audit('import', 'credential', id, '从 Edge CSV 导入密码条目');
      }
      return drafts.length;
    });
  }

  Future<CredentialEntry?> _credentialById(String id) async {
    final row = await (database.select(
      database.credentials,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    return row == null ? null : _credentialFromRow(row);
  }

  @override
  Future<List<CredentialRevision>> credentialHistory(String id) async {
    final rows =
        await (database.select(database.credentialRevisions)
              ..where((table) => table.credentialId.equals(id))
              ..orderBy([(table) => OrderingTerm.desc(table.number)]))
            .get();
    return rows
        .map(
          (row) => CredentialRevision(
            id: row.id,
            credentialId: row.credentialId,
            number: row.number,
            title: row.title,
            username: row.username,
            secret: row.secret,
            website: row.website,
            notes: row.notes,
            createdAt: row.createdAt,
            changeNote: row.changeNote,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> trashCredential(String id) async {
    final changed =
        await (database.update(
          database.credentials,
        )..where((table) => table.id.equals(id))).write(
          CredentialsCompanion(deletedAt: Value(_now), updatedAt: Value(_now)),
        );
    if (changed == 0) throw StateError('密码条目不存在');
    await _audit('trash', 'credential', id, '普通删除，历史 Secret 仍加密保留');
  }

  @override
  Future<void> restoreCredential(String id) => database.transaction(() async {
    final changed =
        await (database.update(
          database.credentials,
        )..where((t) => t.id.equals(id) & t.deletedAt.isNotNull())).write(
          CredentialsCompanion(
            deletedAt: const Value(null),
            updatedAt: Value(_now),
          ),
        );
    if (changed == 0) throw StateError('回收区中没有这条密码');
    await _audit('restore', 'credential', id, '恢复密码条目及历史，已有授权仍保留');
  });

  @override
  Future<void> purgeCredential(String id) async {
    await database.transaction(() async {
      await (database.delete(database.releasePolicies)..where(
            (table) =>
                table.recordType.equals('credential') &
                table.recordId.equals(id),
          ))
          .go();
      final changed = await (database.delete(
        database.credentials,
      )..where((table) => table.id.equals(id))).go();
      if (changed == 0) throw StateError('密码条目不存在');
      await _audit('purge', 'credential', id, '永久清除当前 Vault 中的条目及历史 Secret');
    });
  }

  @override
  Future<ReleasePolicy> getReleasePolicy(
    String recordType,
    String recordId,
  ) async {
    final row =
        await (database.select(database.releasePolicies)..where(
              (table) =>
                  table.recordType.equals(recordType) &
                  table.recordId.equals(recordId),
            ))
            .getSingleOrNull();
    return row == null
        ? ReleasePolicy(recordType: recordType, recordId: recordId)
        : _policyFromRow(row);
  }

  @override
  Future<List<ReleasePolicy>> listReleasePolicies() async {
    final rows = await database.select(database.releasePolicies).get();
    return rows.map(_policyFromRow).toList(growable: false);
  }

  @override
  Future<void> saveReleasePolicy(ReleasePolicy policy) {
    return database.transaction(() async {
      final existing =
          await (database.select(database.releasePolicies)..where(
                (table) =>
                    table.recordType.equals(policy.recordType) &
                    table.recordId.equals(policy.recordId),
              ))
              .getSingleOrNull();
      final companion = ReleasePoliciesCompanion(
        recordType: Value(policy.recordType),
        recordId: Value(policy.recordId),
        recipientName: Value(policy.recipientName.trim()),
        incapacitatedLevel: Value(policy.incapacitated.name),
        deceasedLevel: Value(policy.deceased.name),
        updatedAt: Value(_now),
      );
      if (existing == null) {
        await database.into(database.releasePolicies).insert(companion);
      } else {
        await (database.update(
          database.releasePolicies,
        )..where((table) => table.id.equals(existing.id))).write(companion);
      }
      await _audit('policy', policy.recordType, policy.recordId, '更新交接可见层级');
    });
  }

  @override
  Future<LifeState> currentLifeState() async {
    final row =
        await (database.select(database.lifeStateEvents)
              ..orderBy([(table) => OrderingTerm.desc(table.id)])
              ..limit(1))
            .getSingleOrNull();
    return row == null
        ? LifeState.active
        : LifeState.values.byName(row.toState);
  }

  @override
  Future<List<LifeStateEvent>> lifeStateHistory() async {
    final rows = await (database.select(
      database.lifeStateEvents,
    )..orderBy([(table) => OrderingTerm.desc(table.id)])).get();
    return rows
        .map(
          (row) => LifeStateEvent(
            id: row.id,
            from: LifeState.values.byName(row.fromState),
            to: LifeState.values.byName(row.toState),
            reason: row.reason,
            occurredAt: row.occurredAt,
            isSimulation: row.isSimulation,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> transitionLifeState(LifeState to, {required String reason}) =>
      database.transaction(() async {
        final from = await currentLifeState();
        _stateMachine.validate(from, to);
        await database
            .into(database.lifeStateEvents)
            .insert(
              LifeStateEventsCompanion.insert(
                fromState: from.name,
                toState: to.name,
                reason: reason.trim().isEmpty ? '本人手动切换生命状态' : reason.trim(),
                occurredAt: _now,
              ),
            );
        await _audit(
          'transition',
          'lifeState',
          to.name,
          '${from.name} → ${to.name}',
        );
      });

  @override
  Future<void> resetLifeStateSimulation({required String reason}) =>
      database.transaction(() async {
        final from = await currentLifeState();
        if (from == LifeState.active) return;
        await database
            .into(database.lifeStateEvents)
            .insert(
              LifeStateEventsCompanion.insert(
                fromState: from.name,
                toState: LifeState.active.name,
                reason: reason.trim().isEmpty ? '本人明确重置生活状态' : reason.trim(),
                occurredAt: _now,
              ),
            );
        await _audit(
          'demoReset',
          'lifeState',
          LifeState.active.name,
          '明确重置模拟状态',
        );
      });

  @override
  Future<VaultInsights> insights() async {
    final cards = await listCards();
    final credentials = await listCredentials();
    final staleBefore = _now.subtract(const Duration(days: 180));
    final byKind = <CardKind, int>{};
    for (final card in cards) {
      byKind.update(card.kind, (count) => count + 1, ifAbsent: () => 1);
    }
    return VaultInsights(
      totalCards: cards.length,
      drafts: cards.where((card) => card.status == CardStatus.draft).length,
      confirmed: cards
          .where((card) => card.status == CardStatus.confirmed)
          .length,
      stale: cards.where((card) => card.updatedAt.isBefore(staleBefore)).length,
      credentials: credentials.length,
      byKind: byKind,
    );
  }

  @override
  Future<void> applyVaultMergePlan(VaultMergePlan plan) => database.transaction(
    () async {
      for (final blob in plan.importedBlobs) {
        final existing = await (database.select(
          database.encryptedBlobs,
        )..where((t) => t.id.equals(blob.id))).getSingleOrNull();
        if (existing != null) continue;
        await database
            .into(database.encryptedBlobs)
            .insert(
              EncryptedBlobsCompanion.insert(
                id: blob.id,
                originalName: blob.originalName,
                mediaKind: blob.mediaKind.name,
                mimeType: blob.mimeType,
                relativePath: blob.relativePath,
                byteLength: blob.byteLength,
                sha256: blob.sha256,
                ocrText: Value(blob.ocrText),
                ocrJson: Value(
                  blob.ocrLines.isEmpty ? null : _encodeOcrLines(blob.ocrLines),
                ),
                sensitiveJson: Value(
                  blob.sensitiveMarks.isEmpty
                      ? null
                      : _encodeSensitiveMarks(blob.sensitiveMarks),
                ),
                createdAt: blob.createdAt,
              ),
            );
      }
      for (final record in plan.importedCards) {
        final card = record.card;
        if (await getCard(card.id) != null) {
          throw const FormatException('合并导入的卡片已存在');
        }
        await database
            .into(database.cards)
            .insert(
              CardsCompanion.insert(
                id: card.id,
                title: card.title,
                content: card.content,
                kind: card.kind.name,
                status: card.status.name,
                tagsJson: Value(jsonEncode(card.tags)),
                createdAt: card.createdAt,
                updatedAt: card.updatedAt,
                confirmedAt: Value(card.confirmedAt),
                deletedAt: Value(card.deletedAt),
                parentCardId: Value(card.parentCardId),
                revisionNumber: Value(card.revisionNumber),
              ),
            );
        await _writeMergeRevisions(card.id, record, freshBinding: true);
      }
      for (final record in plan.updatedCards) {
        final card = record.card;
        final existing = await getCard(card.id);
        if (existing == null) {
          throw const FormatException('合并更新的卡片不存在');
        }
        final appended = record.appendedRevisions;
        if (appended.isNotEmpty &&
            appended.first.number <= existing.revisionNumber) {
          throw const FormatException('合并修订编号冲突');
        }
        await (database.update(
          database.cards,
        )..where((t) => t.id.equals(card.id))).write(
          CardsCompanion(
            title: Value(card.title),
            content: Value(card.content),
            kind: Value(card.kind.name),
            status: Value(card.status.name),
            tagsJson: Value(jsonEncode(card.tags)),
            updatedAt: Value(card.updatedAt),
            confirmedAt: Value(card.confirmedAt),
            deletedAt: Value(card.deletedAt),
            parentCardId: Value(card.parentCardId),
            revisionNumber: Value(card.revisionNumber),
          ),
        );
        await _writeMergeRevisions(card.id, record, freshBinding: false);
      }
      await _mergeRelations(plan.importedRelations);
      await _mergeReferences(plan.referenceUnions);
      await _mergeConflicts(plan.conflicts);
      final ledger = plan.missingLedgerJson;
      if (ledger != null) await writeLocalValue('backup.missing', ledger);
      await _audit(
        'merge',
        'vault',
        'local',
        '合并导入：引入 ${plan.importedCards.length} 张卡片，'
            '更新 ${plan.updatedCards.length} 张，'
            '记录 ${plan.conflicts.length} 处未解决',
      );
    },
  );

  /// Writes the appended revision chain with one source row per revision and
  /// merges the `card.originals.<id>` binding. The binding keeps the local
  /// projection current unless the plan names one.
  Future<void> _writeMergeRevisions(
    String cardId,
    MergedCardRecord record, {
    required bool freshBinding,
  }) async {
    for (final revision in record.appendedRevisions) {
      final sourceId = _uuid.v7();
      final blobId = revision.originalBlobId;
      final sourceLabel = blobId == null
          ? revision.sourceLabel
          : (revision.originalSourceLabel ?? revision.sourceLabel);
      final sourceKind = blobId == null
          ? revision.sourceKind
          : (revision.originalSourceKind ?? revision.sourceKind);
      await database
          .into(database.sources)
          .insert(
            SourcesCompanion.insert(
              id: sourceId,
              kind: sourceKind.name,
              label: sourceLabel,
              textExcerpt: Value(revision.content),
              blobId: Value(blobId),
              createdAt: revision.createdAt,
            ),
          );
      await database
          .into(database.cardRevisions)
          .insert(
            CardRevisionsCompanion.insert(
              cardId: cardId,
              number: revision.number,
              title: revision.title,
              content: revision.content,
              tagsJson: Value(jsonEncode(revision.tags)),
              status: revision.status.name,
              sourceKind: revision.sourceKind.name,
              sourceLabel: revision.sourceLabel,
              sourceId: Value(sourceId),
              changeNote: revision.changeNote,
              createdAt: revision.createdAt,
            ),
          );
    }
    final existing = freshBinding ? null : await _binding(cardId);
    if (existing == null &&
        record.currentOriginals == null &&
        record.revisionOriginals.isEmpty) {
      // 从未有过绑定的卡片保持"无绑定"语义：currentCardSources 显示全部来源。
      return;
    }
    final snapshots = <String, dynamic>{
      if (existing != null)
        ...Map<String, dynamic>.from(existing['revisions'] as Map),
    };
    for (final entry in record.revisionOriginals.entries) {
      snapshots['${entry.key}'] = List<String>.of(entry.value);
    }
    final current =
        record.currentOriginals ??
        (existing == null
            ? await _historicalOriginals(cardId)
            : List<String>.from(existing['current'] as List));
    await writeLocalValue(
      _bindingKey(cardId),
      jsonEncode({'version': 1, 'current': current, 'revisions': snapshots}),
    );
  }

  Future<void> _mergeRelations(List<CardRelation> relations) async {
    if (relations.isEmpty) return;
    final rows = await database.select(database.cardRelations).get();
    final known = {
      for (final row in rows) '${row.fromCardId}|${row.toCardId}|${row.kind}',
    };
    for (final relation in relations) {
      final key =
          '${relation.fromCardId}|${relation.toCardId}|${relation.kind.name}';
      if (!known.add(key)) continue;
      if (await getCard(relation.fromCardId) == null ||
          await getCard(relation.toCardId) == null) {
        continue;
      }
      await database
          .into(database.cardRelations)
          .insert(
            CardRelationsCompanion.insert(
              fromCardId: relation.fromCardId,
              toCardId: relation.toCardId,
              kind: relation.kind.name,
              createdAt: _now,
            ),
          );
    }
  }

  Future<void> _mergeReferences(List<MergeCardReferenceUnion> unions) async {
    if (unions.isEmpty) return;
    var references = await cardReferences();
    for (final union in unions) {
      final targets = CardReferenceRules.targets(union.from, union.targets);
      final facts = <String, LifeCard?>{union.from: await getCard(union.from)};
      for (final id in targets) {
        facts[id] = await getCard(id);
      }
      CardReferenceRules.validate(union.from, targets, facts);
      references = CardReferenceRules.replace(references, union.from, targets);
    }
    await writeLocalValue(
      _referencesKey,
      jsonEncode({
        'version': 1,
        'references': [
          for (final r in references) {'from': r.from, 'to': r.to},
        ],
      }),
    );
  }

  Future<void> _mergeConflicts(List<CardMergeConflict> conflicts) async {
    if (conflicts.isEmpty) return;
    final raw = await readLocalValue(CardMergeConflict.storageKey);
    var existing = <String, CardMergeConflict>{};
    if (raw != null) {
      try {
        existing = CardMergeConflict.decodeAll(jsonDecode(raw));
      } on Object {
        existing = {};
      }
    }
    final merged = <String, CardMergeConflict>{...existing};
    for (final conflict in conflicts) {
      merged[conflict.cardId] = conflict;
    }
    await writeLocalValue(
      CardMergeConflict.storageKey,
      jsonEncode({
        'version': CardMergeConflict.version,
        'conflicts': {
          for (final entry in merged.entries) entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  @override
  Future<void> close() => database.close();

  Future<void> _insertCardRevision({
    required String cardId,
    required int number,
    required CardDraft draft,
    required SourceKind sourceKind,
    required String sourceLabel,
    String? sourceId,
    required String changeNote,
    required DateTime createdAt,
  }) async {
    await database
        .into(database.cardRevisions)
        .insert(
          CardRevisionsCompanion.insert(
            cardId: cardId,
            number: number,
            title: draft.title,
            content: draft.content,
            tagsJson: Value(jsonEncode(DraftRules.normalizedTags(draft.tags))),
            status: draft.status.name,
            sourceKind: sourceKind.name,
            sourceLabel: sourceLabel,
            sourceId: Value(sourceId),
            changeNote: changeNote,
            createdAt: createdAt,
          ),
        );
    final binding = await _binding(cardId);
    if (binding != null) {
      final snapshots = Map<String, dynamic>.from(binding['revisions'] as Map);
      snapshots['$number'] = binding['current'];
      binding['revisions'] = snapshots;
      await writeLocalValue(_bindingKey(cardId), jsonEncode(binding));
    }
  }

  Future<void> _insertCredentialRevision(
    String credentialId,
    int number,
    CredentialDraft draft,
    String changeNote,
    DateTime createdAt,
  ) {
    return database
        .into(database.credentialRevisions)
        .insert(
          CredentialRevisionsCompanion.insert(
            credentialId: credentialId,
            number: number,
            title: draft.title.trim(),
            username: draft.username.trim(),
            secret: draft.secret,
            website: draft.website.trim(),
            notes: draft.notes.trim(),
            changeNote: changeNote,
            createdAt: createdAt,
          ),
        );
  }

  Future<void> _audit(
    String action,
    String entityType,
    String entityId,
    String description,
  ) {
    return database
        .into(database.auditEvents)
        .insert(
          AuditEventsCompanion.insert(
            action: action,
            entityType: entityType,
            entityId: entityId,
            description: description,
            occurredAt: _now,
          ),
        );
  }

  LifeCard _cardFromRow(CardRow row) => LifeCard(
    id: row.id,
    title: row.title,
    content: row.content,
    kind: CardKind.values.byName(row.kind),
    status: CardStatus.values.byName(row.status),
    tags: _decodeTags(row.tagsJson),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    confirmedAt: row.confirmedAt,
    deletedAt: row.deletedAt,
    parentCardId: row.parentCardId,
    revisionNumber: row.revisionNumber,
  );

  CardRevision _cardRevisionFromRow(CardRevisionRow row) => CardRevision(
    id: row.id,
    cardId: row.cardId,
    number: row.number,
    title: row.title,
    content: row.content,
    tags: _decodeTags(row.tagsJson),
    status: CardStatus.values.byName(row.status),
    sourceKind: SourceKind.values.byName(row.sourceKind),
    sourceLabel: row.sourceLabel,
    changeNote: row.changeNote,
    createdAt: row.createdAt,
  );

  CredentialEntry _credentialFromRow(CredentialRow row) => CredentialEntry(
    id: row.id,
    title: row.title,
    username: row.username,
    secret: row.secret,
    website: row.website,
    notes: row.notes,
    tags: _decodeTags(row.tagsJson),
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
    deletedAt: row.deletedAt,
    revisionNumber: row.revisionNumber,
  );

  VaultBlob _blobFromRow(EncryptedBlobRow row) => VaultBlob(
    id: row.id,
    originalName: row.originalName,
    mediaKind: BlobMediaKind.values.byName(row.mediaKind),
    mimeType: row.mimeType,
    relativePath: row.relativePath,
    byteLength: row.byteLength,
    sha256: row.sha256,
    createdAt: row.createdAt,
    ocrText: row.ocrText,
    ocrLines: _decodeOcrLines(row.ocrJson),
    sensitiveMarks: _decodeSensitiveMarks(row.sensitiveJson),
  );

  String _encodeOcrLines(List<OcrLine> lines) => jsonEncode(
    lines
        .map(
          (line) => <String, Object?>{
            'text': line.text,
            'left': line.left,
            'top': line.top,
            'right': line.right,
            'bottom': line.bottom,
            'order': line.order,
            'confidence': line.confidence,
          },
        )
        .toList(growable: false),
  );

  List<OcrLine> _decodeOcrLines(String? value) {
    if (value == null || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) {
          final map = Map<String, Object?>.from(item);
          return OcrLine(
            text: map['text']! as String,
            left: (map['left']! as num).toDouble(),
            top: (map['top']! as num).toDouble(),
            right: (map['right']! as num).toDouble(),
            bottom: (map['bottom']! as num).toDouble(),
            order: map['order']! as int,
            confidence: (map['confidence'] as num?)?.toDouble(),
          );
        })
        .toList(growable: false);
  }

  String _encodeSensitiveMarks(List<SensitiveMark> marks) => jsonEncode(
    marks
        .map(
          (mark) => <String, Object>{
            'lineOrder': mark.lineOrder,
            'kind': mark.kind.name,
          },
        )
        .toList(growable: false),
  );

  List<SensitiveMark> _decodeSensitiveMarks(String? value) {
    if (value == null || value.isEmpty) return const [];
    final decoded = jsonDecode(value);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) {
          final map = Map<String, Object?>.from(item);
          return SensitiveMark(
            lineOrder: map['lineOrder']! as int,
            kind: SensitiveFieldKind.values.byName(map['kind']! as String),
          );
        })
        .toList(growable: false);
  }

  String _readableByteLength(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  ReleasePolicy _policyFromRow(ReleasePolicyRow row) => ReleasePolicy(
    recordType: row.recordType,
    recordId: row.recordId,
    recipientName: row.recipientName,
    incapacitated: VisibilityLevel.values.byName(row.incapacitatedLevel),
    deceased: VisibilityLevel.values.byName(row.deceasedLevel),
  );

  List<String> _decodeTags(String source) =>
      (jsonDecode(source) as List).whereType<String>().toList(growable: false);
}
