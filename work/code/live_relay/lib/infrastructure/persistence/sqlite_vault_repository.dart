import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/domain/entities.dart';
import '../../core/domain/lifecycle.dart';
import '../../core/ports/vault_repository.dart';
import 'app_database.dart';

class SqliteVaultRepository implements VaultRepository {
  SqliteVaultRepository(this.database, {Uuid? uuid})
    : _uuid = uuid ?? const Uuid();

  final AppDatabase database;
  final Uuid _uuid;
  final LifeStateMachine _stateMachine = const LifeStateMachine();

  DateTime get _now => DateTime.now().toUtc();

  @override
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
  }) async {
    final statement = database.select(database.cards)
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]);
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
  }) async {
    _validateCardDraft(draft);
    final id = _uuid.v7();
    final sourceId = _uuid.v7();
    final now = _now;
    final tags = _normalizedTags(draft.tags);
    await database
        .into(database.sources)
        .insert(
          SourcesCompanion.insert(
            id: sourceId,
            kind: sourceKind.name,
            label: sourceLabel,
            textExcerpt: Value(draft.content),
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
      _validateCardDraft(draft);
      final existing = await getCard(id);
      if (existing == null || existing.isDeleted) {
        throw StateError('卡片不存在');
      }
      final now = _now;
      final revision = existing.revisionNumber + 1;
      final tags = _normalizedTags(draft.tags);
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
          confirmedAt: Value(
            draft.status == CardStatus.confirmed
                ? (existing.confirmedAt ?? now)
                : null,
          ),
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
  Future<LifeCard> confirmCard(String id) async {
    final card = await getCard(id);
    if (card == null) throw StateError('卡片不存在');
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
  }

  @override
  Future<List<LifeCard>> splitCard(String id, List<CardDraft> parts) {
    if (parts.length < 2) throw const FormatException('拆分至少需要两张卡片');
    return database.transaction(() async {
      final original = await getCard(id);
      if (original == null || original.isDeleted) throw StateError('卡片不存在');
      final now = _now;
      final revision = original.revisionNumber + 1;
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
        draft: CardDraft(
          title: original.title,
          content: original.content,
          kind: original.kind,
          status: CardStatus.split,
          tags: original.tags,
        ),
        sourceKind: SourceKind.ownerInput,
        sourceLabel: '本人整理',
        changeNote: '拆分为 ${parts.length} 张独立卡片',
        createdAt: now,
      );
      final children = <LifeCard>[];
      for (final part in parts) {
        final child = await _insertCard(
          part,
          sourceKind: SourceKind.ownerInput,
          sourceLabel: '由「${original.title}」拆分',
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
    if (memberIds.length < 2) throw const FormatException('组合至少需要两张卡片');
    return database.transaction(() async {
      final uniqueIds = memberIds.toSet();
      if (uniqueIds.length != memberIds.length) {
        throw const FormatException('组合卡片不能包含重复成员');
      }
      for (final id in memberIds) {
        if (await getCard(id) == null) throw StateError('组合成员不存在');
      }
      final bundle = await _insertCard(
        CardDraft(
          title: title.trim(),
          content: '组合展示 ${memberIds.length} 张独立卡片',
          kind: CardKind.bundle,
          tags: const ['组合'],
        ),
        sourceKind: SourceKind.ownerInput,
        sourceLabel: '本人组合',
      );
      final now = _now;
      for (final memberId in memberIds) {
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
  Future<List<VaultBlob>> listBlobs() async {
    final rows = await (database.select(
      database.encryptedBlobs,
    )..orderBy([(table) => OrderingTerm.desc(table.createdAt)])).get();
    return rows.map(_blobFromRow).toList(growable: false);
  }

  @override
  Future<LifeCard> registerBlob(VaultBlob blob) {
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
      await _audit('import', 'blob', blob.id, '加密保存原始资料并创建来源卡片');
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
            draft,
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
  Future<List<CredentialEntry>> listCredentials({String query = ''}) async {
    final statement = database.select(database.credentials)
      ..where((table) => table.deletedAt.isNull())
      ..orderBy([(table) => OrderingTerm.desc(table.updatedAt)]);
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
      _validateCredentialDraft(draft);
      final now = _now;
      final tags = _normalizedTags(draft.tags);
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
        _validateCredentialDraft(draft);
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
                tagsJson: Value(jsonEncode(_normalizedTags(draft.tags))),
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
  Future<void> transitionLifeState(
    LifeState to, {
    required String reason,
  }) async {
    final from = await currentLifeState();
    _stateMachine.validate(from, to);
    await database
        .into(database.lifeStateEvents)
        .insert(
          LifeStateEventsCompanion.insert(
            fromState: from.name,
            toState: to.name,
            reason: reason.trim().isEmpty ? 'MVP 人工模拟' : reason.trim(),
            occurredAt: _now,
          ),
        );
    await _audit(
      'transition',
      'lifeState',
      to.name,
      '${from.name} → ${to.name}',
    );
  }

  @override
  Future<void> resetLifeStateSimulation({required String reason}) async {
    final from = await currentLifeState();
    if (from == LifeState.active) return;
    await database
        .into(database.lifeStateEvents)
        .insert(
          LifeStateEventsCompanion.insert(
            fromState: from.name,
            toState: LifeState.active.name,
            reason: reason.trim().isEmpty ? '重置 MVP 模拟' : reason.trim(),
            occurredAt: _now,
          ),
        );
    await _audit('demoReset', 'lifeState', LifeState.active.name, '明确重置模拟状态');
  }

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
  }) {
    return database
        .into(database.cardRevisions)
        .insert(
          CardRevisionsCompanion.insert(
            cardId: cardId,
            number: number,
            title: draft.title,
            content: draft.content,
            tagsJson: Value(jsonEncode(_normalizedTags(draft.tags))),
            status: draft.status.name,
            sourceKind: sourceKind.name,
            sourceLabel: sourceLabel,
            sourceId: Value(sourceId),
            changeNote: changeNote,
            createdAt: createdAt,
          ),
        );
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

  List<String> _normalizedTags(Iterable<String> tags) => tags
      .map((tag) => tag.trim())
      .where((tag) => tag.isNotEmpty)
      .toSet()
      .toList(growable: false);

  void _validateCardDraft(CardDraft draft) {
    if (draft.title.trim().isEmpty) throw const FormatException('标题不能为空');
    if (draft.content.trim().isEmpty) throw const FormatException('内容不能为空');
  }

  void _validateCredentialDraft(CredentialDraft draft) {
    if (draft.title.trim().isEmpty) throw const FormatException('条目名称不能为空');
    if (draft.secret.isEmpty) throw const FormatException('密码不能为空');
  }
}
