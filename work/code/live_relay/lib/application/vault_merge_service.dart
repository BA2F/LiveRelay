import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:collection/collection.dart';
import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

import '../core/domain/entities.dart';
import '../core/domain/vault_merge.dart';
import '../core/ports/transfer_medium.dart';
import '../core/ports/vault_archive.dart';
import '../core/ports/vault_installation.dart';
import '../core/ports/vault_maintenance.dart';
import '../core/ports/vault_repository.dart';
import '../core/security/vault_header_v3.dart';
import '../core/storage/vault_failures.dart';
import 'merge/card_merge_planner.dart';
import 'vault_backup_service.dart';

/// 合并导入报告中的一处未解决冲突。
class MergeConflictSummary {
  const MergeConflictSummary({
    required this.cardId,
    required this.title,
    required this.kind,
  });

  final String cardId;
  final String title;
  final MergeConflictKind kind;
}

/// 合并导入中一张卡片的引用并集变化。
class MergeReferenceChange {
  const MergeReferenceChange({required this.cardId, required this.added});

  final String cardId;
  final List<String> added;
}

/// Result of one B-mode merge import（合并导入）。Everything the UI needs for
/// the import report, badges and banners; no keys, paths or directory names.
class MergeImportReport {
  const MergeImportReport({
    required this.databaseName,
    required this.mergedAt,
    required this.mergedCards,
    required this.importedCards,
    required this.fastForwardedCards,
    required this.forkedCards,
    required this.adoptedDeletions,
    required this.keptLocalDeletionConflicts,
    required this.localDeletionConflicts,
    required this.conflicts,
    required this.referenceChanges,
    required this.importedBlobs,
    required this.copiedBlobs,
    required this.reencryptedBlobs,
    required this.reusedLocalBlobs,
    required this.owedBlobs,
    required this.importedRelations,
    required this.unmergedCategories,
    required this.volumesConsumed,
    required this.pendingVolumes,
    required this.volumeErrors,
    required this.remainingMissingOriginals,
    required this.warnings,
  });

  final String databaseName;
  final DateTime mergedAt;

  /// Cards whose record now contains content from the other device
  /// (imported + fast-forwarded + forked).
  final int mergedCards;
  final int importedCards;
  final int fastForwardedCards;
  final int forkedCards;

  /// 对方删除且本机未改动：已采用对方的删除。
  final int adoptedDeletions;

  /// 对方删除且本机有改动：保留本机版并标记。
  final int keptLocalDeletionConflicts;

  /// 本机删除且对方有改动：保持本机删除并标记（对方分叉段保留在历史中）。
  final int localDeletionConflicts;

  /// 冲突清单（徽标/横幅/报告共用）。
  final List<MergeConflictSummary> conflicts;
  final List<MergeReferenceChange> referenceChanges;

  final int importedBlobs;

  /// 包内实带、同钥直接拷入的密文原件数。
  final int copiedBlobs;
  final int reencryptedBlobs;
  final int reusedLocalBlobs;
  final int owedBlobs;
  final int importedRelations;

  /// 未合并类别清单（保留本机）。
  final List<String> unmergedCategories;

  final int volumesConsumed;
  final List<String> pendingVolumes;
  final List<String> volumeErrors;
  final int remainingMissingOriginals;
  final List<String> warnings;
}

/// B-mode merge engine（合并导入）. Coordinates one authenticated merge: the
/// local vault is the base copy, the other device's package contributes only
/// cards, originals, references and owed-original ledger entries — credentials
/// and every other local category are untouched（一期不合密码库）。The session
/// credentials and header do not change (C-mode replacement does the
/// opposite).
class VaultMergeService {
  VaultMergeService({
    required this._session,
    required this._archive,
    required this._backup,
    required VaultInstallation Function() restoreTransaction,
  }) : _createRestoreTransaction = restoreTransaction;

  final VaultMaintenance _session;
  final VaultArchive _archive;
  final VaultBackupService _backup;
  final VaultInstallation Function() _createRestoreTransaction;
  late final VaultInstallation _restoreTransaction =
      _createRestoreTransaction();

  /// 未合并类别清单：合并保留本机版本，报告如实列出。
  static const unmergedCategories = <String>[
    '密码条目（一期不合并）',
    '身份、接收者与交接资料',
    '交接可见性（发布策略）',
    '生命状态历史',
    'Agent 计划与会话',
    '工作台状态（引用除外）',
    'transfer 索引',
  ];

  /// Reads the unresolved merge markers (`workbench.merge.v1`). Empty when
  /// nothing is pending; throws while the vault is locked.
  Future<Map<String, CardMergeConflict>> mergeConflicts() async {
    final raw = await _session.repository.readLocalValue(
      CardMergeConflict.storageKey,
    );
    if (raw == null) return const {};
    try {
      return Map.unmodifiable(CardMergeConflict.decodeAll(jsonDecode(raw)));
    } on Object {
      return const {};
    }
  }

  /// Clears the marker after a card is settled (adopting the other version or
  /// a direct edit). Safe to call when no marker exists.
  Future<void> clearMergeConflict(String cardId) =>
      _session.runMutation(() => _clearConflicts({cardId}));

  Future<void> clearMergeConflicts(Iterable<String> cardIds) =>
      _session.runMutation(() => _clearConflicts(cardIds.toSet()));

  Future<void> _clearConflicts(Set<String> cardIds) async {
    if (cardIds.isEmpty) return;
    final repository = _session.repository;
    final raw = await repository.readLocalValue(CardMergeConflict.storageKey);
    if (raw == null) return;
    Map<String, CardMergeConflict> decoded;
    try {
      decoded = CardMergeConflict.decodeAll(jsonDecode(raw));
    } on Object {
      return;
    }
    final remaining = {...decoded}
      ..removeWhere((id, _) => cardIds.contains(id));
    if (remaining.length == decoded.length) return;
    await repository.writeLocalValue(
      CardMergeConflict.storageKey,
      jsonEncode({
        'version': CardMergeConflict.version,
        'conflicts': {
          for (final entry in remaining.entries)
            entry.key: entry.value.toJson(),
        },
      }),
    );
  }

  /// Merges the other device's database package from [medium] into this
  /// vault. Requires the vault to be unlocked and the package to carry the
  /// same `vaultId`; the credential is the other device's current unlock
  /// password or recovery credential.
  Future<MergeImportReport> mergeFromMedium(
    TransferMedium medium, {
    required String databaseName,
    required String credential,
    required void Function() clearUnlockedData,
    required Future<void> Function() refreshUnlockedData,
  }) async {
    final outcome = await _session.exclusiveMaintenance(
      () => _mergeCore(
        medium,
        databaseName,
        credential,
        clearUnlockedData,
        refreshUnlockedData,
      ),
    );
    // 欠账原件：安装完成后按对方快照消费介质上配对的原件卷（与 C 模式一致，
    // 卷留在介质上可重复使用）。这一步走常规补充导入的独立门控。
    final consumed = await _consumeVolumes(medium, outcome.foreignSnapshotId);
    final remaining = await _backup.missingCount();
    return MergeImportReport(
      databaseName: outcome.databaseName,
      mergedAt: outcome.mergedAt,
      mergedCards:
          outcome.importedCards +
          outcome.fastForwardedCards +
          outcome.forkedCards,
      importedCards: outcome.importedCards,
      fastForwardedCards: outcome.fastForwardedCards,
      forkedCards: outcome.forkedCards,
      adoptedDeletions: outcome.adoptedDeletions,
      keptLocalDeletionConflicts: outcome.keptLocalDeletionConflicts,
      localDeletionConflicts: outcome.localDeletionConflicts,
      conflicts: List.unmodifiable(outcome.conflicts),
      referenceChanges: List.unmodifiable(outcome.referenceChanges),
      importedBlobs: outcome.importedBlobs,
      copiedBlobs: outcome.copiedBlobs,
      reencryptedBlobs: outcome.reencryptedBlobs,
      reusedLocalBlobs: outcome.reusedLocalBlobs,
      owedBlobs: outcome.owedBlobs,
      importedRelations: outcome.importedRelations,
      unmergedCategories: unmergedCategories,
      volumesConsumed: consumed.consumed.length,
      pendingVolumes: remaining > 0 ? consumed.pending : const [],
      volumeErrors: consumed.errors,
      remainingMissingOriginals: remaining,
      warnings: List.unmodifiable(outcome.warnings),
    );
  }

  Future<_MergeCoreOutcome> _mergeCore(
    TransferMedium medium,
    String databaseName,
    String credential,
    void Function() clearUnlockedData,
    Future<void> Function() refreshUnlockedData,
  ) async {
    if (!_session.isUnlocked) throw StateError('请先解锁加密资料库');
    final epoch = _session.operationEpoch;
    final identity = await _session.archiveIdentity();
    if (identity == null) {
      throw const LifeVaultArchiveException('合并导入需要新一代安全格式的资料库');
    }
    final localKey = await _session.withMasterKey(
      (key) async => Uint8List.fromList(key),
    );
    StagedLifeVault? foreignStage;
    VaultRepository? foreignRepository;
    VaultRepository? mergedRepository;
    Uint8List? foreignKey;
    // The staged manifest may alias this buffer; it stays alive until the
    // merge core finishes (same contract as `restore`).
    Uint8List? archiveBytes;
    Directory? mergeStaging;
    var transactionStarted = false;
    try {
      await _session.directory.parent.create(recursive: true);
      archiveBytes = await medium.read(databaseName);
      final staged = await _archive.stage(
        archiveBytes: archiveBytes,
        stagingParent: _session.directory.parent,
      );
      foreignStage = staged;
      if (staged.kind == 'attachments') {
        throw const LifeVaultArchiveException('原件补充包不能用于合并导入');
      }
      final metadata = await _session.readStagedHeader(staged.directory);
      if (metadata == null) {
        throw const LifeVaultArchiveException('.lvault 缺少 Vault header');
      }
      if (metadata.formatVersion != 3) {
        throw const LifeVaultArchiveException('该数据库包来自旧格式资料库，请改用替换导入');
      }
      final foreignHeader = VaultHeaderV3.decode(
        await File(path.join(staged.directory.path, 'vault-header.json'))
            .readAsBytes(),
      );
      // 权威校验：只有同一套资料库（vaultId 相同）才能合并。
      if (foreignHeader.vaultId != identity.vaultId) {
        throw const LifeVaultArchiveException('该数据库包属于另一套资料库，请改用替换导入');
      }
      foreignKey = await _session.authenticateStaged(
        staged.directory,
        credential,
        metadata,
      );
      await _archive.verifyAuthentication(
        staged: staged,
        masterKey: foreignKey,
      );
      _checkEpoch(epoch);

      // 合并库以本机副本为基础：header 与 key 保持本机（本机凭证不变）。
      // 数据库只在复制副本时短暂挂起，随后立刻恢复本机会话，避免失败路径
      // 留下"已解锁但没有仓库"的状态。
      await _session.suspendDatabase();
      _checkEpoch(epoch);
      try {
        mergeStaging = await _session.directory.parent.createTemp(
          'liverelay-restore-',
        );
        await _copyVaultDirectory(_session.directory, mergeStaging);
      } finally {
        if (epoch == _session.operationEpoch) {
          await _session.openWithKey(localKey);
          _checkEpoch(epoch);
        }
      }
      final merged = await _session.openTemporary(mergeStaging, localKey);
      mergedRepository = merged;
      final foreign = await _session.openTemporary(
        staged.directory,
        foreignKey,
      );
      foreignRepository = foreign;
      _checkEpoch(epoch);
      final mergedAt = DateTime.now().toUtc();
      final outcome = await _buildMergePlan(
        merged: merged,
        foreign: foreign,
        foreignStage: staged,
        foreignKey: foreignKey,
        localKey: localKey,
        mergeStaging: mergeStaging,
        databaseName: databaseName,
        mergedAt: mergedAt,
      );
      _checkEpoch(epoch);
      await merged.applyVaultMergePlan(outcome.plan);
      _checkEpoch(epoch);
      await foreign.close();
      foreignRepository = null;
      await merged.close();
      mergedRepository = null;

      await _session.close();
      final installingEpoch = _session.operationEpoch;
      clearUnlockedData();
      transactionStarted = true;
      try {
        final notice = await _restoreTransaction.install(
          mergeStaging,
          verifyInstalled: () async {
            _checkEpoch(installingEpoch);
            await _session.openWithKey(localKey);
            await _session.reloadHeader();
            _checkEpoch(installingEpoch);
          },
          closeInstalled: () async {
            await _session.close();
            clearUnlockedData();
          },
        );
        _checkEpoch(installingEpoch);
        // 本机凭证不变，header 未换：安装后直接解锁。与恢复不同，设备指纹
        // 密钥槽仍指向同一个 master key，因此不清除设备密钥。
        _session.markUnlocked();
        try {
          await refreshUnlockedData();
        } on Object {
          // 合并已安装且可打开；投影刷新失败不回滚有效资料库。
        }
        return outcome.withInstallNotice(notice);
      } on Object {
        await _session.close();
        clearUnlockedData();
        try {
          await _restoreTransaction.recover();
          await _session.inspectRecoveredHeader();
        } on Object {
          _session.fail();
          throw const VaultRecoveryException();
        }
        throw const LifeVaultArchiveException('合并未完成；资料库已保留，请使用对应密码重新解锁');
      }
    } finally {
      try {
        await foreignRepository?.close();
      } on Object {
        // 合并已判定失败时，临时句柄关闭失败只影响清理的彻底程度。
      }
      try {
        await mergedRepository?.close();
      } on Object {
        // 同上。
      }
      try {
        if (!transactionStarted &&
            mergeStaging != null &&
            await mergeStaging.exists()) {
          await mergeStaging.delete(recursive: true);
        }
      } finally {
        if (foreignStage != null) {
          try {
            if (await foreignStage.directory.exists()) {
              await foreignStage.directory.delete(recursive: true);
            }
          } on Object {
            // 受控相邻目录，残留不影响下次合并。
          }
        }
        _wipe(localKey);
        if (foreignKey != null) _wipe(foreignKey);
        if (archiveBytes != null) _wipe(archiveBytes);
      }
    }
  }

  /// Builds the whole plan from both authenticated repositories, copies the
  /// originals the other package carries into the merged staging, and records
  /// owed originals in the merged ledger.
  Future<_MergeCoreOutcome> _buildMergePlan({
    required VaultRepository merged,
    required VaultRepository foreign,
    required StagedLifeVault foreignStage,
    required Uint8List foreignKey,
    required Uint8List localKey,
    required Directory mergeStaging,
    required String databaseName,
    required DateTime mergedAt,
  }) async {
    final warnings = <String>[];
    final localCards = <String, LifeCard>{
      for (final card in [
        ...await merged.listCards(),
        ...await merged.listCards(recycled: true),
      ])
        card.id: card,
    };
    final foreignCards = <String, LifeCard>{
      for (final card in [
        ...await foreign.listCards(),
        ...await foreign.listCards(recycled: true),
      ])
        card.id: card,
    };

    // ---- blob 层：合并库 = 本机 ∪ 对方 ----
    final localBlobs = await merged.listBlobs();
    final localById = {for (final blob in localBlobs) blob.id: blob};
    final localByPath = {
      for (final blob in localBlobs) blob.relativePath: blob,
    };
    final sameKey = const ListEquality<int>().equals(localKey, foreignKey);
    final importedBlobs = <VaultBlob>[];
    final ledger = _decodeLedger(await merged.readLocalValue('backup.missing'));
    var ledgerChanged = false;
    var directCopies = 0, reencrypted = 0, reusedLocal = 0, owed = 0;
    for (final blob in await foreign.listBlobs()) {
      if (localById.containsKey(blob.id)) continue;
      if (localByPath.containsKey(blob.relativePath)) {
        warnings.add('原件路径冲突，保留本机版本：${blob.originalName}');
        continue;
      }
      importedBlobs.add(blob);
      final foreignFile = File(
        path.join(foreignStage.directory.path, blob.relativePath),
      );
      if (await foreignFile.exists()) {
        final bytes = await foreignFile.readAsBytes();
        try {
          if (sameKey) {
            await _session.writeBlobCiphertext(
              target: mergeStaging,
              blob: blob,
              bytes: bytes,
            );
            directCopies++;
          } else {
            await _session.copyBlobUnderKey(
              source: foreignStage.directory,
              target: mergeStaging,
              oldKey: foreignKey,
              newKey: localKey,
              blob: blob,
            );
            reencrypted++;
          }
        } finally {
          _wipe(bytes);
        }
        continue;
      }
      final descriptor = foreignStage.omitted[blob.relativePath];
      if (descriptor is! Map) {
        throw const LifeVaultArchiveException('数据库包缺少原件且没有缺失清单，无法合并');
      }
      if (await _fileMatchesDescriptor(
        File(path.join(mergeStaging.path, blob.relativePath)),
        descriptor,
      )) {
        reusedLocal++;
        continue;
      }
      owed++;
      final ledgerKey = blob.relativePath;
      if (!ledger.containsKey(ledgerKey)) {
        ledger[ledgerKey] = {
          ...Map<String, Object?>.from(descriptor),
          'key': base64UrlEncode(foreignKey),
          'snapshotId': foreignStage.snapshotId,
        };
        ledgerChanged = true;
      }
    }

    // ---- 卡片合并（纯对象进/计划出）----
    final imported = <MergedCardRecord>[];
    final updated = <MergedCardRecord>[];
    final conflicts = <CardMergeConflict>[];
    final conflictSummaries = <MergeConflictSummary>[];
    final aliveAfterMerge = <String>{};
    var fastForwarded = 0, forked = 0, adoptedDeletions = 0;
    var keptLocalDeletions = 0, localDeletionConflicts = 0;
    final ids = {...localCards.keys, ...foreignCards.keys};
    for (final id in ids) {
      final localCard = localCards[id], foreignCard = foreignCards[id];
      final decision = await planCardMerge(
        local: await _sideFacts(merged, id, localCard),
        foreign: await _sideFacts(foreign, id, foreignCard),
        mergedAt: mergedAt,
      );
      switch (decision.action) {
        case CardMergeAction.importCard:
          imported.add(decision.record!);
          aliveAfterMerge.add(id);
        case CardMergeAction.fastForward:
          updated.add(decision.record!);
          fastForwarded++;
          aliveAfterMerge.add(id);
        case CardMergeAction.fork:
          updated.add(decision.record!);
          forked++;
          conflicts.add(decision.conflict!);
          conflictSummaries.add(
            MergeConflictSummary(
              cardId: id,
              title: localCard?.title ?? id,
              kind: decision.conflict!.kind,
            ),
          );
          if (!decision.conflict!.localDeleted) aliveAfterMerge.add(id);
          if (decision.conflict!.localDeleted) localDeletionConflicts++;
        case CardMergeAction.adoptDeletion:
          updated.add(decision.record!);
          adoptedDeletions++;
        case CardMergeAction.keepLocal:
          conflicts.add(decision.conflict!);
          keptLocalDeletions++;
          conflictSummaries.add(
            MergeConflictSummary(
              cardId: id,
              title: localCard?.title ?? id,
              kind: decision.conflict!.kind,
            ),
          );
          aliveAfterMerge.add(id);
        case CardMergeAction.unchanged:
          if (localCard != null && !localCard.isDeleted) {
            aliveAfterMerge.add(id);
          }
      }
    }

    // ---- 引用：按卡 union ----
    final localReferences = await merged.cardReferences();
    final foreignReferences = await foreign.cardReferences();
    final localTargets = <String, List<String>>{};
    for (final reference in localReferences) {
      (localTargets[reference.from] ??= []).add(reference.to);
    }
    final foreignTargets = <String, List<String>>{};
    for (final reference in foreignReferences) {
      (foreignTargets[reference.from] ??= []).add(reference.to);
    }
    final unions = <MergeCardReferenceUnion>[];
    final referenceChanges = <MergeReferenceChange>[];
    for (final entry in foreignTargets.entries) {
      final from = entry.key;
      if (!aliveAfterMerge.contains(from)) continue;
      final localSide = localTargets[from] ?? const <String>[];
      final union = <String>{...localSide};
      final added = <String>[];
      for (final target in entry.value) {
        if (target == from) continue;
        if (union.add(target)) added.add(target);
      }
      if (added.isEmpty) continue;
      final filtered = <String>[];
      var dropped = 0;
      for (final target in union) {
        if (aliveAfterMerge.contains(target)) {
          filtered.add(target);
        } else {
          dropped++;
        }
      }
      if (dropped > 0) {
        warnings.add('引用目标已不在资料库，未纳入：$dropped 处（卡片 $from）');
      }
      if (filtered.length > 200) {
        warnings.add('引用超过单卡上限，超出部分未合并（卡片 $from）');
        filtered.removeRange(200, filtered.length);
      }
      unions.add(MergeCardReferenceUnion(from: from, targets: filtered));
      referenceChanges.add(
        MergeReferenceChange(cardId: from, added: List.unmodifiable(added)),
      );
    }

    // ---- 拆分/组合关系并集 ----
    final existingRelations = <String>{};
    for (final id in localCards.keys) {
      for (final relation in await merged.relationsForCard(id)) {
        existingRelations.add(_relationKey(relation));
      }
    }
    final existingCardsAfter = <String>{
      ...localCards.keys,
      ...imported.map((record) => record.card.id),
    };
    final relations = <CardRelation>[];
    final seenRelations = <String>{};
    for (final id in foreignCards.keys) {
      for (final relation in await foreign.relationsForCard(id)) {
        final key = _relationKey(relation);
        if (existingRelations.contains(key) || !seenRelations.add(key)) {
          continue;
        }
        if (!existingCardsAfter.contains(relation.fromCardId) ||
            !existingCardsAfter.contains(relation.toCardId)) {
          continue;
        }
        relations.add(relation);
      }
    }

    return _MergeCoreOutcome(
      plan: VaultMergePlan(
        importedCards: imported,
        updatedCards: updated,
        importedBlobs: importedBlobs,
        importedRelations: relations,
        referenceUnions: unions,
        conflicts: conflicts,
        missingLedgerJson: ledgerChanged ? jsonEncode(ledger) : null,
      ),
      foreignSnapshotId: foreignStage.snapshotId,
      databaseName: databaseName,
      mergedAt: mergedAt,
      importedCards: imported.length,
      fastForwardedCards: fastForwarded,
      forkedCards: forked,
      adoptedDeletions: adoptedDeletions,
      keptLocalDeletionConflicts: keptLocalDeletions,
      localDeletionConflicts: localDeletionConflicts,
      conflicts: conflictSummaries,
      referenceChanges: referenceChanges,
      importedBlobs: importedBlobs.length,
      copiedBlobs: directCopies,
      reencryptedBlobs: reencrypted,
      reusedLocalBlobs: reusedLocal,
      owedBlobs: owed,
      importedRelations: relations.length,
      warnings: warnings,
    );
  }

  Future<CardMergeSide> _sideFacts(
    VaultRepository repository,
    String cardId,
    LifeCard? card,
  ) async {
    if (card == null) return const CardMergeSide();
    final revisions = (await repository.cardHistory(cardId)).reversed.toList();
    final sources = await repository.cardSources(cardId);
    final labels = <String, ({String label, SourceKind kind})>{
      for (final source in sources)
        if (source.blobId != null)
          source.blobId!: (label: source.label, kind: source.kind),
    };
    final raw = await repository.readLocalValue('card.originals.$cardId');
    List<String> current;
    Map<int, List<String>> snapshots = {};
    if (raw != null) {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      current = (data['current'] as List? ?? const []).cast<String>();
      for (final entry in (data['revisions'] as Map? ?? const {}).entries) {
        final number = int.tryParse('${entry.key}');
        if (number == null || entry.value is! List) continue;
        snapshots[number] = (entry.value as List).cast<String>();
      }
    } else {
      // 没有绑定的卡片按现状语义（cardSources 全部）合成一个当前集合。
      current = <String>{
        for (final source in sources)
          if (source.blobId != null) source.blobId!,
      }.toList();
    }
    return CardMergeSide(
      card: card,
      revisions: revisions,
      currentOriginals: current,
      originalSnapshots: snapshots,
      originalLabels: labels,
    );
  }

  String _relationKey(CardRelation relation) =>
      '${relation.fromCardId}|${relation.toCardId}|${relation.kind.name}';

  /// Recursive copy of the vault directory (header, database and blobs),
  /// skipping only writer temporaries.
  Future<void> _copyVaultDirectory(Directory source, Directory target) async {
    await target.create(recursive: true);
    await for (final entity in source.list(
      recursive: true,
      followLinks: false,
    )) {
      final relative = path.relative(entity.path, from: source.path);
      if (relative.endsWith('.tmp')) continue;
      if (entity is Directory) {
        await Directory(path.join(target.path, relative))
            .create(recursive: true);
        continue;
      }
      if (entity is! File) continue;
      final destination = File(path.join(target.path, relative));
      await destination.parent.create(recursive: true);
      await entity.copy(destination.path);
    }
  }

  Map<String, Object?> _decodeLedger(String? raw) {
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map ? Map<String, Object?>.from(decoded) : {};
    } on Object {
      return {};
    }
  }

  Future<bool> _fileMatchesDescriptor(
    File file,
    Map<Object?, Object?> descriptor,
  ) async {
    final size = descriptor['size'], sha256 = descriptor['sha256'];
    if (size is! int || sha256 is! String) return false;
    try {
      if (!await file.exists() || await file.length() != size) return false;
      final sink = Sha256().newHashSink();
      await for (final chunk in file.openRead()) {
        sink.add(chunk);
      }
      sink.close();
      return base64UrlEncode((await sink.hash()).bytes) == sha256;
    } on Object {
      return false;
    }
  }

  Future<bool> _owedForSnapshot(String snapshotId) async {
    if (!_session.isUnlocked) return false;
    final raw = await _session.repository.readLocalValue('backup.missing');
    if (raw == null) return false;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      return decoded.values.any(
        (value) => value is Map && value['snapshotId'] == snapshotId,
      );
    } on Object {
      return false;
    }
  }

  /// Consumes the original volumes on the medium that pair with the other
  /// package's snapshot. Every consumed blob is verified against the merged
  /// ledger before it is accepted.
  Future<({List<String> consumed, List<String> pending, List<String> errors})>
  _consumeVolumes(TransferMedium medium, String? snapshotId) async {
    final consumed = <String>[], pending = <String>[], errors = <String>[];
    if (snapshotId == null) {
      return (consumed: consumed, pending: pending, errors: errors);
    }
    try {
      for (final entry in await medium.list()) {
        if (!entry.name.endsWith('.lvault')) continue;
        final prefix = await medium.readPrefix(entry.name, 64 * 1024);
        final summary = _archive.inspectContainerPrefix(prefix);
        if (summary?.kind != 'attachments' ||
            summary?.snapshotId != snapshotId) {
          continue;
        }
        if (!await _owedForSnapshot(snapshotId)) break;
        final bytes = await medium.read(entry.name);
        try {
          await _backup.importSupplement(bytes);
          consumed.add(entry.name);
        } on Object catch (error) {
          errors.add('${entry.name}：$error');
          pending.add(entry.name);
        } finally {
          _wipe(bytes);
        }
      }
    } on Object catch (error) {
      errors.add('$error');
    }
    return (consumed: consumed, pending: pending, errors: errors);
  }

  void _checkEpoch(int epoch) {
    if (epoch != _session.operationEpoch) throw StateError('资料库操作已取消');
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
}

/// Everything the public report needs, assembled inside the maintenance gate.
class _MergeCoreOutcome {
  const _MergeCoreOutcome({
    required this.plan,
    required this.foreignSnapshotId,
    required this.databaseName,
    required this.mergedAt,
    required this.importedCards,
    required this.fastForwardedCards,
    required this.forkedCards,
    required this.adoptedDeletions,
    required this.keptLocalDeletionConflicts,
    required this.localDeletionConflicts,
    required this.conflicts,
    required this.referenceChanges,
    required this.importedBlobs,
    required this.copiedBlobs,
    required this.reencryptedBlobs,
    required this.reusedLocalBlobs,
    required this.owedBlobs,
    required this.importedRelations,
    required this.warnings,
  });

  final VaultMergePlan plan;
  final String? foreignSnapshotId;
  final String databaseName;
  final DateTime mergedAt;
  final int importedCards;
  final int fastForwardedCards;
  final int forkedCards;
  final int adoptedDeletions;
  final int keptLocalDeletionConflicts;
  final int localDeletionConflicts;
  final List<MergeConflictSummary> conflicts;
  final List<MergeReferenceChange> referenceChanges;
  final int importedBlobs;
  final int copiedBlobs;
  final int reencryptedBlobs;
  final int reusedLocalBlobs;
  final int owedBlobs;
  final int importedRelations;
  final List<String> warnings;

  _MergeCoreOutcome withInstallNotice(String? notice) => _MergeCoreOutcome(
    plan: plan,
    foreignSnapshotId: foreignSnapshotId,
    databaseName: databaseName,
    mergedAt: mergedAt,
    importedCards: importedCards,
    fastForwardedCards: fastForwardedCards,
    forkedCards: forkedCards,
    adoptedDeletions: adoptedDeletions,
    keptLocalDeletionConflicts: keptLocalDeletionConflicts,
    localDeletionConflicts: localDeletionConflicts,
    conflicts: conflicts,
    referenceChanges: referenceChanges,
    importedBlobs: importedBlobs,
    copiedBlobs: copiedBlobs,
    reencryptedBlobs: reencryptedBlobs,
    reusedLocalBlobs: reusedLocalBlobs,
    owedBlobs: owedBlobs,
    importedRelations: importedRelations,
    warnings: [?notice, ...warnings],
  );
}
