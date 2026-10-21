import 'dart:async';
import 'dart:io' show FileSystemException;

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import '../../application/vault_session.dart';
import '../../application/vault_snapshot_query.dart';
import '../../application/local_handoff_service.dart';
import '../../application/handoff_view_service.dart';
import '../../application/handoff_delivery_service.dart';
import '../../application/recipient_service.dart';
import '../../application/vault_security_service.dart';
import '../../application/device_transfer_service.dart';
import '../../application/vault_merge_service.dart';
import '../../core/domain/vault_merge.dart';
import '../../application/transfer/transfer_models.dart';
import '../../application/transfer/webdav_connection_service.dart';
import '../../core/transfer/webdav_connection.dart';
import '../../core/security/recovery_credential.dart';
import '../../application/draft_agent_service.dart';
import 'speech_service.dart';
import '../contracts/preview_session.dart';
import '../../application/vault_backup_service.dart';
import '../../core/ports/transfer_medium.dart';

import '../../core/ai/ai_privacy.dart';
import '../../application/card_summary.dart';
import '../../application/workbench/card_references.dart';
import '../../application/device_capabilities.dart';
import '../../core/domain/entities.dart';
import '../../core/ai/review_source.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/review_action_proposal.dart';
import '../../core/ports/ai_provider.dart';
import '../../core/ports/ai_conversation_provider.dart';
import '../../core/ports/device_factor_protection.dart';
import '../../application/vault_content_service.dart';
import '../../application/vault_records_application.dart';
import '../../core/security/chinese_passphrase.dart';
import '../../core/storage/vault_failures.dart';
import '../../core/security/vault_key_manager.dart';
import '../../core/ai/ai_provider_settings.dart';
import '../../core/ai/outbound_consent.dart';
import '../../application/agent/agent_settings_service.dart';
import '../../application/ai/outbound_consent_service.dart';
import '../../application/agent/agent_service.dart';
import '../../application/agent/conversation_application.dart';
import '../../application/workbench/workspace_state_store.dart';
import '../../application/agent/agent_review_service.dart';
import '../../application/import/edge_password_csv_importer.dart';

export '../../application/vault_session.dart' show VaultSessionState;

class AppController extends ChangeNotifier implements PreviewSession {
  AppController({
    required this.records,
    this.capabilities = const DeviceCapabilities(DevicePlatform.other),
    required this._session,
    required this._backup,
    required this._transfer,
    required this._merge,
    required this._webDav,
    required this._content,
    required this._agentSettings,
    required this._outboundConsent,
    required this._agent,
    required this._agentReview,
    required this._snapshotQuery,
    required this._prepareEnvironment,
    this._speechService,
    this._conversationApplication,
    this._securityService,
    this.handoff,
    this.handoffView,
    this.delivery,
    this.recipient,
  }) {
    _agentSubscriptions = [
      _agent.activity.listen((_) => notifyListeners()),
      _agentSettings.changes.listen((_) => notifyListeners()),
      _outboundConsent.changes.listen((_) => notifyListeners()),
      _session.changes.listen((_) {
        if (!_disposed) {
          if (!_session.isUnlocked) _clearUnlockedData();
          notifyListeners();
        }
      }),
      _snapshotQuery.changes.listen((snapshot) {
        if (!_disposed &&
            isUnlocked &&
            snapshot.sessionGeneration == _session.sessionGeneration) {
          _applySnapshot(snapshot);
          notifyListeners();
        }
      }),
      if (_securityService != null)
        _securityService.changes.listen((_) => notifyListeners()),
    ];
    _speechService?.addListener(notifyListeners);
  }

  /// 合并导入遗留的未解决标记（`workbench.merge.v1`），按卡片 id 索引；
  /// 列表徽标、卡片横幅与导入报告都读它。
  Map<String, CardMergeConflict> mergeConflicts = const {};

  Map<String, Object?> ownerProfile = const {
    'name': '本人',
    'contact': '',
    'note': '',
  };
  Future<void> saveOwnerProfile(String name, String contact, String note) =>
      _run(() async {
        await handoff!.saveProfile(name, contact, note);
        ownerProfile = await handoff!.profile();
      });
  final LocalHandoffService? handoff;
  final HandoffViewService? handoffView;
  final HandoffDeliveryService? delivery;
  final RecipientService? recipient;

  /// 本机是否已有独立接收者身份；正式入口据此决定是否显示接收者入口。
  bool get recipientExists => recipient?.exists ?? false;
  final VaultSecurityService? _securityService;
  bool get supportsModernSecurity => _securityService != null;
  String get securityProgress => _securityService?.stage ?? '';
  Future<String> generateRecovery() async {
    final r = RecoveryCredential.generate();
    try {
      return await r.encode();
    } finally {
      r.dispose();
    }
  }

  Future<void> setupModernVault({
    required String password,
    required String recoveryText,
    required String recoveryConfirmation,
    bool chinese = false,
    int? wordCount,
    bool biometric = false,
  }) => _run(() async {
    if (recoveryText != recoveryConfirmation) {
      throw const FormatException('恢复凭证确认不一致');
    }
    final r = await RecoveryCredential.parse(recoveryText);
    try {
      await _session.createModern(
        password: password,
        recovery: r,
        usesChinesePassphrase: chinese,
        wordCount: wordCount,
        enableBiometric: biometric,
      );
      await _refreshUnlockedData();
    } finally {
      r.dispose();
    }
  });
  Future<void> unlockDaily({
    String? password,
    Uint8List? keyFile,
    String preferred = 'password',
  }) => _run(() async {
    await _session.unlockDaily(
      password: password,
      keyFile: keyFile,
      preferred: preferred,
    );
    await _refreshUnlockedData();
  });
  Future<void> beginRecovery(String text) => _run(() async {
    await _session.unlockWithRecovery(text);
    _clearUnlockedData();
  });
  Future<void> configureSecurity({
    required String oldPassword,
    required String newPassword,
    required String recoveryText,
    required String recoveryConfirmation,
    String policy = 'any',
    Uint8List? oldKeyFile,
    Uint8List? newKeyFile,
    bool biometric = false,
    bool chinese = false,
    int? wordCount,
  }) => _run(() async {
    try {
      await _securityService!.configure(
        oldPassword: oldPassword,
        newPassword: newPassword,
        recoveryText: recoveryText,
        recoveryConfirmation: recoveryConfirmation,
        policy: policy,
        oldKeyFile: oldKeyFile,
        newKeyFile: newKeyFile,
        biometric: biometric,
        chinese: chinese,
        wordCount: wordCount,
      );
      await _refreshUnlockedData();
    } catch (_) {
      _clearUnlockedData();
      rethrow;
    }
  });
  final SpeechService? _speechService;
  SpeechService? get speech => _speechService;
  final VaultRecordsApplication records;
  final VaultSession _session;
  final VaultBackupService _backup;
  final DeviceTransferService _transfer;
  final VaultMergeService _merge;
  final WebDavConnectionService _webDav;
  final VaultContentService _content;
  final AgentSettingsService _agentSettings;
  final OutboundConsentService _outboundConsent;
  final AgentService _agent;
  final AgentReviewService _agentReview;
  final VaultSnapshotQuery _snapshotQuery;
  final ConversationApplication? _conversationApplication;
  late final WorkspaceStateStore workspaceState = WorkspaceStateStore(_session);
  late final ConversationApplication conversationApplication =
      _conversationApplication ??
      ConversationApplication(
        vault: _session,
        settings: _agentSettings,
        agent: _agent,
        review: _agentReview,
        content: _content,
        snapshots: _snapshotQuery,
      );
  late final List<StreamSubscription<Object?>> _agentSubscriptions;
  final Future<void> Function() _prepareEnvironment;

  VaultSessionState get sessionState => _session.state;
  VaultHeaderMetadata? get header => _session.header;
  bool get biometricAvailable => _session.biometricAvailable;
  bool _disposed = false;
  bool get isAgentBusy => _agent.isBusy;
  void cancelAgentTask() => _agent.cancel();
  final exitCleanups = <Future<void> Function()>{};
  @override
  void registerPreviewCleanup(Future<void> Function() cleanup) =>
      exitCleanups.add(cleanup);
  @override
  void unregisterPreviewCleanup(Future<void> Function() cleanup) =>
      exitCleanups.remove(cleanup);
  bool _uiBusy = false;
  bool get isBusy => _uiBusy || _session.isWriting || _session.isMaintaining;
  set isBusy(bool value) => _uiBusy = value;
  bool agentCommandsAvailable = false;
  OutboundConsentService get outboundConsent => _outboundConsent;
  Future<void> grantOutbound(
    OutboundDestination destination,
    OutboundKind kind,
  ) => _run(() => _outboundConsent.grant(destination, kind));
  Future<void> revokeOutbound(String destinationId) =>
      _run(() => _outboundConsent.revoke(destinationId));
  AiProviderSettings get aiSettings => _agentSettings.settings;
  List<AiProviderSettings> get aiProfiles => _agentSettings.profiles;
  int get aiConfigurationGeneration => _agentSettings.generation;
  String? lastError;
  String? get recoveryNotice => _backup.recoveryNotice;

  List<LifeCard> cards = const [];
  List<CardReference> cardReferences = const [];
  Future<void> setCardReferences(String from, List<String> targets) =>
      _recordMutation(() => records.setCardReferences(from, targets));
  List<LifeCard> recycledCards = const [];
  List<CredentialEntry> recycledCredentials = const [];
  DateTime? lastBackupExport;
  List<VaultBlob> blobs = const [];
  Set<String> recycledBlobIds = const {};
  List<CredentialEntry> credentials = const [];
  List<ReleasePolicy> releasePolicies = const [];
  List<LifeStateEvent> lifeStateHistory = const [];
  LifeState lifeState = LifeState.active;
  VaultInsights insights = const VaultInsights(
    totalCards: 0,
    drafts: 0,
    confirmed: 0,
    stale: 0,
    credentials: 0,
    byKind: {},
  );

  @override
  bool get isUnlocked => sessionState == VaultSessionState.unlocked;
  DeviceCapabilities capabilities;
  void setDemonstrationCapabilities(DeviceCapabilities value) {
    capabilities = value;
    notifyListeners();
  }

  FeatureCapability capability(AppFeature feature) => capabilities.feature(
    feature,
    biometricAvailable: biometricAvailable,
    agentConfigured:
        aiSettings.isConfigured && aiSettings.protocol == AiProtocol.responses,
    speechInstalled: _speechService?.installed ?? false,
  );

  List<CardSummary> findInformationCards(
    String query, {
    CardKind? kind,
    CardStatus? status,
    bool passwordsOnly = false,
  }) {
    final summaries = <CardSummary>[
      if (!passwordsOnly)
        ...findCards(
          query,
          kind: kind,
          status: status,
        ).map(CardSummary.fromRecord),
      if (kind == null && status == null)
        ...findCredentials(query).map(CardSummary.fromRecord),
    ];
    summaries.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(summaries);
  }

  Future<void> initialize() async {
    try {
      await _prepareEnvironment();
      await _agentSettings.initialize();
      await _outboundConsent.initialize();
      try {
        // 只读取接收者身份是否存在，决定正式入口是否显示接收者入口。
        await recipient?.initialize();
      } on Object {
        /* 接收者身份读取失败不影响所有者资料库。 */
      }
      try {
        await _speechService?.refresh();
        agentCommandsAvailable = await _agent.commandAvailable();
      } on Object {
        /* Speech setup does not block vault access. */
      }
      await _session.prepare();
      await _backup.recover();
      await _session.inspect();
    } on Object catch (error) {
      lastError = _messageFor(error);
      _session.fail();
    }
    notifyListeners();
  }

  ChinesePassphrase generatePassphrase({int count = 6}) =>
      _session.generatePassphrase(count: count);

  Future<void> setupVault({
    required String password,
    required bool usesChinesePassphrase,
    int? wordCount,
    bool enableBiometric = false,
  }) => _run(() async {
    await _session.setupVault(
      password: password,
      usesChinesePassphrase: usesChinesePassphrase,
      wordCount: wordCount,
      enableBiometric: enableBiometric,
    );
    await _refreshUnlockedData();
  });

  Future<void> unlockWithPassword(String password) => _run(() async {
    await _session.unlockWithPassword(password);
    await _refreshUnlockedData();
  });

  Future<void> unlockWithBiometric() => _run(() async {
    await _session.unlockWithBiometric();
    await _refreshUnlockedData();
  });

  Future<void> setBiometricEnabled(bool enabled) =>
      _run(() => _session.setBiometricEnabled(enabled));

  Future<void> enableBiometricWithPassword(String password) =>
      _run(() => _session.enableBiometricWithPassword(password));

  Future<Uint8List> exportVault(String password) async {
    if (!isUnlocked) throw StateError('请先解锁加密资料库');
    late Uint8List result;
    await _run(() async {
      result = await _backup.export(
        password,
        refreshUnlockedData: _refreshUnlockedData,
      );
    });
    return result;
  }

  Future<({Uint8List database, Uint8List attachments})> exportSplitVault(
    String credential,
  ) async {
    late ({Uint8List database, Uint8List attachments}) result;
    await _run(() async {
      result = await _backup.exportSplit(credential, _refreshUnlockedData);
    });
    return result;
  }

  Future<int> missingOriginalCount() => _backup.missingCount();
  Future<void> importOriginalSupplement(Uint8List bytes) =>
      _run(() => _backup.importSupplement(bytes));

  Future<void> restoreVault(Uint8List bytes, String backupPassword) => _run(
    () => _backup.restore(
      bytes,
      backupPassword,
      clearUnlockedData: _clearUnlockedData,
      refreshUnlockedData: _refreshUnlockedData,
    ),
  );

  /// Read-only medium scan; does not take the busy gate so the transfer page
  /// can refresh its listings freely.
  Future<TransferMediumScan> scanTransferMedium(TransferMedium medium) =>
      _transfer.scan(medium);

  Future<BackupPreview> inspectTransferMedium(
    TransferMedium medium,
    String databaseName,
    String credential,
  ) async {
    late BackupPreview preview;
    await _run(() async {
      preview = await _transfer.inspectMedium(medium, databaseName, credential);
    });
    return preview;
  }

  Future<TransferExportOutcome> exportToMedium(
    TransferMedium medium,
    String credential,
  ) async {
    late TransferExportOutcome outcome;
    await _run(() async {
      outcome = await _backup.exportTransferToMedium(
        medium,
        credential,
        refreshUnlockedData: _refreshUnlockedData,
        payloadLimit: DeviceTransferService.defaultPayloadLimit,
      );
    });
    return outcome;
  }

  Future<TransferImportReport> importFromMedium(
    TransferMedium medium, {
    required String databaseName,
    required String credential,
    String? preExportCredential,
  }) async {
    late TransferImportReport report;
    await _run(() async {
      report = await _transfer.importFromMedium(
        medium,
        databaseName: databaseName,
        credential: credential,
        preExportCredential: preExportCredential,
        clearUnlockedData: _clearUnlockedData,
        refreshUnlockedData: _refreshUnlockedData,
      );
    });
    return report;
  }

  Future<TransferImportReport> importPendingVolumes(
    TransferMedium medium,
  ) async {
    late TransferImportReport report;
    await _run(() async {
      report = await _transfer.importPendingVolumes(medium);
    });
    return report;
  }

  /// 本机资料库的 vaultId（v3 格式）；旧格式或读取失败返回 null，
  /// 导入界面据此判断介质包能否合并。
  Future<String?> archiveVaultId() async {
    try {
      return (await _session.archiveIdentity())?.vaultId;
    } on Object {
      return null;
    }
  }

  /// B 模式合并导入：以本机为底，引入介质包中另一台设备的卡片改动。
  /// 引擎侧自取独占维护，这里只包 busy 门与错误呈现（与 restoreVault 同形）。
  Future<MergeImportReport> mergeFromMedium(
    TransferMedium medium, {
    required String databaseName,
    required String credential,
  }) async {
    if (!isUnlocked) throw StateError('请先解锁资料库再合并导入');
    late MergeImportReport report;
    await _run(() async {
      report = await _merge.mergeFromMedium(
        medium,
        databaseName: databaseName,
        credential: credential,
        clearUnlockedData: _clearUnlockedData,
        refreshUnlockedData: _refreshUnlockedData,
      );
    });
    return report;
  }

  /// 采用另一台设备的版本：写一条等于对方版本的修订，清除待选标记。
  /// 本机已删除的卡片会先恢复再采用。
  Future<void> adoptForeignMergeVersion(String cardId) async {
    final conflict = mergeConflicts[cardId];
    final foreignHead = conflict?.foreignHead;
    if (conflict == null || foreignHead == null) {
      throw StateError('这条卡片没有可采用的另一设备版本');
    }
    await _recordMutation(() async {
      if (conflict.localDeleted) await records.restoreCard(cardId);
      await records.restoreCardRevision(cardId, foreignHead);
      await _merge.clearMergeConflict(cardId);
    });
    _dropMergeConflict(cardId);
  }

  /// 采用另一台设备的删除：把卡片移入回收区，清除待选标记。
  Future<void> adoptForeignMergeDeletion(String cardId) async {
    final conflict = mergeConflicts[cardId];
    if (conflict == null || !conflict.foreignDeleted) {
      throw StateError('这条卡片没有另一设备的删除可采纳');
    }
    await _recordMutation(() async {
      await records.trashCard(cardId);
      await _merge.clearMergeConflict(cardId);
    });
    _dropMergeConflict(cardId);
  }

  /// 卡片在本机产生新修订（编辑、恢复修订）即视为已做出选择，清掉待选标记。
  Future<void> _clearMergeAfterEdit(String cardId) async {
    if (!mergeConflicts.containsKey(cardId)) return;
    await _merge.clearMergeConflict(cardId);
    _dropMergeConflict(cardId);
  }

  void _dropMergeConflict(String cardId) {
    if (!mergeConflicts.containsKey(cardId)) return;
    mergeConflicts = Map.of(mergeConflicts)..remove(cardId);
    notifyListeners();
  }

  /// Device-local cloud drive connection; read-only and cheap after the
  /// first load, so it stays outside the busy gate.
  Future<WebDavConnection?> webDavConnection() => _webDav.current();
  Future<void> saveWebDavConnection(WebDavConnection connection) =>
      _run(() => _webDav.save(connection));
  Future<void> clearWebDavConnection() => _run(() => _webDav.clear());

  Future<void> lock() async {
    cancelAgentTask();
    _speechService?.cancelTranscription();
    try {
      await _session.close();
    } finally {
      _clearUnlockedData();
      notifyListeners();
    }
  }

  void _clearUnlockedData() {
    ownerProfile = const {'name': '本人', 'contact': '', 'note': ''};
    mergeConflicts = const {};
    cards = const [];
    cardReferences = const [];
    recycledCards = const [];
    recycledCredentials = const [];
    lastBackupExport = null;
    blobs = const [];
    recycledBlobIds = const {};
    credentials = const [];
    releasePolicies = const [];
    lifeStateHistory = const [];
    insights = const VaultInsights(
      totalCards: 0,
      drafts: 0,
      confirmed: 0,
      stale: 0,
      credentials: 0,
      byKind: {},
    );
  }

  Future<void> refresh({String cardQuery = '', String credentialQuery = ''}) =>
      _run(_refreshUnlockedData);

  // Page queries are projections of the complete unlocked snapshot. A refresh,
  // mutation or handoff preview can never overwrite another page's data.
  List<LifeCard> findCards(String query, {CardKind? kind, CardStatus? status}) {
    final needle = query.trim().toLowerCase();
    return cards
        .where(
          (c) =>
              (kind == null || c.kind == kind) &&
              (status == null || c.status == status) &&
              '${c.title} ${c.content} ${c.tags.join(' ')}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
  }

  List<CredentialEntry> findCredentials(String query) {
    final needle = query.trim().toLowerCase();
    return credentials
        .where(
          (c) =>
              '${c.title} ${c.username} ${c.website} ${c.notes} ${c.tags.join(' ')}'
                  .toLowerCase()
                  .contains(needle),
        )
        .toList();
  }

  Future<void> markBackupExported() =>
      _recordMutation(records.markBackupExported);

  Future<BackupPreview> inspectBackup(Uint8List bytes, String password) async {
    late BackupPreview preview;
    await _run(() async {
      preview = await _backup.inspect(bytes, password);
    });
    return preview;
  }

  Future<void> createCard(
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String sourceLabel = '本人输入',
  }) => _recordMutation(
    () => records.createCard(
      draft,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
    ),
  );

  Future<void> updateCard(
    String id,
    CardDraft draft, {
    String changeNote = '更新卡片',
  }) async {
    await _recordMutation(
      () => records.updateCard(id, draft, changeNote: changeNote),
    );
    await _clearMergeAfterEdit(id);
  }

  Future<void> confirmCard(String id) =>
      _recordMutation(() => records.confirmCard(id));

  Future<void> splitCard(String id, List<CardDraft> parts) =>
      _recordMutation(() => records.splitCard(id, parts));

  Future<void> combineCards(String title, List<String> memberIds) =>
      _recordMutation(() => records.combineCards(title, memberIds));

  Future<void> restoreCard(String id) =>
      _recordMutation(() => records.restoreCard(id));
  Future<void> restoreCredential(String id) =>
      _recordMutation(() => records.restoreCredential(id));
  Future<List<LifeCard>> cardsForBlob(String blobId) =>
      records.cardsForBlob(blobId);
  Future<List<CardSource>> cardSources(String id) => records.cardSources(id);
  Future<List<CardSource>> currentCardSources(String id) =>
      records.currentCardSources(id);
  Future<void> setCardOriginals(String id, List<String> blobIds) =>
      _recordMutation(() => records.setCardOriginals(id, blobIds));

  /// 把新附件写入加密原件并关联到这条卡片；一步完成导入与关联。
  Future<void> attachOriginalToCard(
    String cardId, {
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async {
    try {
      await _recordMutation(
        () => records.attachOriginalToCard(
          cardId,
          bytes: bytes,
          originalName: originalName,
          mimeType: mimeType,
          mediaKind: mediaKind,
        ),
      );
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<void> restoreCardRevision(String id, int number) async {
    await _recordMutation(() => records.restoreCardRevision(id, number));
    await _clearMergeAfterEdit(id);
  }

  Future<CardDeletionPreview> previewCardDeletion(List<String> ids) =>
      records.previewCardDeletion(ids);
  Future<void> trashCards(
    List<String> ids, {
    bool recycleUnsharedOriginals = false,
  }) => _recordMutation(
    () => records.trashCards(
      ids,
      recycleUnsharedOriginals: recycleUnsharedOriginals,
    ),
  );
  Future<void> restoreOriginal(String id) =>
      _recordMutation(() => records.restoreOriginal(id));
  Future<LifeCard?> getCard(String id) => records.getCard(id);
  Future<String?> readWorkbenchState() =>
      workspaceState.read(WorkspaceRecord.layout);
  Future<void> writeWorkbenchState(String value) =>
      workspaceState.write(WorkspaceRecord.layout, value);
  Future<String?> readWorkbenchExtensions() =>
      workspaceState.read(WorkspaceRecord.extensions);
  Future<void> writeWorkbenchExtensions(String value) =>
      workspaceState.write(WorkspaceRecord.extensions, value);
  Future<void> createCardFromOriginal(String blobId, CardDraft draft) =>
      _recordMutation(() => records.createCardFromOriginal(blobId, draft));

  Future<void> trashCard(String id) =>
      _recordMutation(() => records.trashCard(id));

  Future<LifeCard> importOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async {
    late LifeCard card;
    try {
      await _run(() async {
        card = await records.importOriginal(
          bytes: bytes,
          originalName: originalName,
          mimeType: mimeType,
          mediaKind: mediaKind,
        );
        _applyCurrentSnapshot();
      });
      return card;
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<Uint8List> readOriginal(String blobId) => records.readOriginal(blobId);

  Future<LifeCard> runOcr(String blobId) async {
    late LifeCard card;
    await _run(() async {
      card = await records.runOcr(blobId);
      _applyCurrentSnapshot();
    });
    return card;
  }

  Future<void> saveSensitiveMarks(String blobId, List<SensitiveMark> marks) =>
      _recordMutation(() => records.saveSensitiveMarks(blobId, marks));

  String previewAiDisclosure(String blobId, List<SensitiveMark> marks) {
    final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
    if (blob == null) throw StateError('原始资料不存在');
    return _agent.previewOriginal(blob, marks);
  }

  Future<int> organizeWithAi(String blobId, List<SensitiveMark> marks) async {
    var count = 0;
    await _run(() async {
      final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
      if (blob == null) throw StateError('原始资料不存在');
      count = await _agent.organizeOriginal(blob, marks);
      await _refreshUnlockedData();
    });
    return count;
  }

  Future<void> saveAiSettings({
    required String endpoint,
    required String model,
    String? apiKey,
    AiProtocol? protocol,
    bool? supportsImages,
    bool? supportsFiles,
    bool? supportsAudio,
    String? profileId,
    String? name,
    List<String>? models,
    bool create = false,
  }) => _run(
    () => _agentSettings.save(
      endpoint: endpoint,
      model: model,
      apiKey: apiKey,
      protocol: protocol,
      supportsImages: supportsImages,
      supportsFiles: supportsFiles,
      supportsAudio: supportsAudio,
      profileId: profileId,
      name: name,
      models: models,
      create: create,
    ),
  );

  Future<void> selectAiProfile(String id, String model) =>
      _run(() => _agentSettings.select(id, model));
  Future<void> removeAiProfile(String id) => _run(() async {
    // 服务配置移除后，它的外发授权不再有意义；重新添加时按首次处理。
    final profile = aiProfiles.where((p) => p.id == id).firstOrNull;
    if (profile != null) {
      await _outboundConsent.revoke(
        OutboundDestination.ai(
          profileId: profile.id,
          endpoint: profile.endpoint,
          name: profile.name,
        ).id,
      );
    }
    await _agentSettings.remove(id);
  });
  Future<void> clearAiSettings() => _run(_agentSettings.clear);

  String previewAgentDisclosure(String text, List<SensitiveMark> marks) =>
      _agent.prepare(text, marks).redactedText;

  Future<AgentDraftBatch> proposeAgentDrafts(
    String text,
    List<SensitiveMark> marks, {
    bool allowCommands = false,
  }) async {
    late AgentDraftBatch batch;
    await _run(() async {
      if (isAgentBusy) throw StateError('请先结束当前 Agent 请求');
      batch = await _agent.propose(text, marks, allowCommands: allowCommands);
    });
    return batch;
  }

  AiTokenizedPayload prepareConversationText(
    String text,
    List<SensitiveMark> marks,
  ) => _agent.prepare(text, marks);
  Future<String?> readConversationState() =>
      conversationApplication.readConversationState();
  Future<void> writeConversationState(String value) =>
      conversationApplication.writeConversationState(value);
  Future<AiConversationResponse> converse(
    String text,
    List<Map<String, Object?>> history, {
    List<Map<String, Object?>>? inputContent,
    List<ReviewTarget> reviewTargets = const [],
  }) async {
    // Network waiting owns an Agent slot, not the local mutation gate. Card
    // edits and encrypted workbench buffers can save while a reply is pending.
    if (_disposed) throw const FormatException('资料库已关闭');
    if (isBusy || isAgentBusy) throw const FormatException('请等待当前操作完成');
    try {
      return await _agent.converse(
        text,
        history,
        inputContent: inputContent,
        reviewTargets: reviewTargets,
      );
    } on Object catch (error) {
      throw FormatException(_messageFor(error));
    }
  }

  Future<void> acceptConversationCards(
    String reviewId,
    String sourceText,
    List<AiCardSuggestion> suggestions, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  }) => _runWrite(() async {
    await _agentReview.accept(
      reviewId,
      sourceText,
      suggestions,
      providerLabel: providerLabel,
      originalIds: originalIds,
      reviewSource: reviewSource,
      actions: actions,
    );
    await _refreshUnlockedData();
  });

  Future<void> saveAgentDrafts(AgentDraftBatch batch) => _runWrite(() async {
    await _agentReview.saveDrafts(batch);
    await _refreshUnlockedData();
  });

  Future<void> saveSpeechDraft(String text, {String? blobId}) =>
      _recordMutation(() => records.saveSpeechDraft(text, blobId: blobId));

  Future<List<CardRevision>> cardHistory(String id) => records.cardHistory(id);

  Future<ReviewSource?> cardReviewSource(String id) =>
      records.cardReviewSource(id);

  Future<List<ReviewActions>?> reviewedActions(String reviewId) =>
      _agentReview.reviewedActions(reviewId);

  Future<List<CardRelation>> cardRelations(String id) =>
      records.cardRelations(id);

  Future<void> saveCredential(CredentialDraft draft, {String? id}) =>
      _recordMutation(() => records.saveCredential(draft, id: id));

  Future<void> trashCredential(String id) =>
      _recordMutation(() => records.trashCredential(id));

  Future<void> purgeCredential(String id) =>
      _recordMutation(() => records.purgeCredential(id));

  Future<EdgePasswordImportResult> importEdgePasswords(Uint8List bytes) async {
    try {
      late EdgePasswordImportResult parsed;
      await _run(() async {
        parsed = await records.importEdgePasswords(bytes);
        _applyCurrentSnapshot();
      });
      return parsed;
    } finally {
      // The presentation busy gate may reject before entering the use case.
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  Future<List<CredentialRevision>> credentialHistory(String id) =>
      records.credentialHistory(id);

  Future<ReleasePolicy> releasePolicy(String recordType, String recordId) =>
      records.releasePolicy(recordType, recordId);

  Future<void> saveReleasePolicy(ReleasePolicy policy) =>
      _recordMutation(() => records.saveReleasePolicy(policy));

  Future<void> transitionLifeState(LifeState state, {required String reason}) =>
      _recordMutation(() => records.transitionLifeState(state, reason: reason));

  Future<void> resetLifeStateSimulation() => _recordMutation(
    () => records.resetLifeStateSimulation(reason: '本人明确重置生活状态'),
  );

  List<LifeCard> get executorCards {
    if (lifeState == LifeState.active) return const [];
    final policiesById = {
      for (final policy in releasePolicies)
        if (policy.recordType == 'card') policy.recordId: policy,
    };
    return cards
        .where(
          (card) =>
              (policiesById[card.id]?.visibleAt(lifeState) ??
                  VisibilityLevel.hidden) !=
              VisibilityLevel.hidden,
        )
        .toList(growable: false);
  }

  List<CredentialEntry> get executorCredentials {
    if (lifeState == LifeState.active) return const [];
    final policiesById = {
      for (final policy in releasePolicies)
        if (policy.recordType == 'credential') policy.recordId: policy,
    };
    return credentials
        .where(
          (entry) =>
              (policiesById[entry.id]?.visibleAt(lifeState) ??
                  VisibilityLevel.hidden) !=
              VisibilityLevel.hidden,
        )
        .toList(growable: false);
  }

  VisibilityLevel executorVisibilityFor(LifeCard card) {
    for (final policy in releasePolicies) {
      if (policy.recordType == 'card' && policy.recordId == card.id) {
        return policy.visibleAt(lifeState);
      }
    }
    return VisibilityLevel.hidden;
  }

  VisibilityLevel executorCredentialVisibilityFor(CredentialEntry entry) {
    for (final policy in releasePolicies) {
      if (policy.recordType == 'credential' && policy.recordId == entry.id) {
        return policy.visibleAt(lifeState);
      }
    }
    return VisibilityLevel.hidden;
  }

  Future<void> _refreshUnlockedData() async {
    final snapshot = await _snapshotQuery.load(
      includeOwnerProfile: handoff != null,
    );
    if (_disposed ||
        !isUnlocked ||
        snapshot.sessionGeneration != _session.sessionGeneration) {
      throw StateError('资料库已关闭或重开，本次查询已丢弃');
    }
    _applySnapshot(snapshot);
    mergeConflicts = await _merge.mergeConflicts();
  }

  void _applySnapshot(VaultSnapshot snapshot) {
    cards = snapshot.cards;
    cardReferences = snapshot.references;
    blobs = snapshot.blobs;
    recycledBlobIds = snapshot.recycledBlobIds;
    credentials = snapshot.credentials;
    releasePolicies = snapshot.policies;
    lifeStateHistory = snapshot.lifeStateHistory;
    lifeState = snapshot.lifeState;
    insights = snapshot.insights;
    recycledCards = snapshot.recycledCards;
    recycledCredentials = snapshot.recycledCredentials;
    lastBackupExport = snapshot.lastBackupExport;
    if (handoff != null) ownerProfile = snapshot.ownerProfile;
  }

  Future<void> _runWrite(Future<void> Function() action) =>
      _run(() => _session.runMutation(action));

  void _applyCurrentSnapshot() {
    final snapshot = _snapshotQuery.current;
    if (snapshot != null) _applySnapshot(snapshot);
  }

  Future<void> _recordMutation<T>(Future<T> Function() operation) =>
      _run(() async {
        await operation();
        _applyCurrentSnapshot();
      });

  Future<void> _run(Future<void> Function() action) async {
    if (isBusy) throw StateError('请等待当前操作完成');
    isBusy = true;
    lastError = null;
    notifyListeners();
    try {
      await action();
    } on Object catch (error) {
      lastError = _messageFor(error);
      rethrow;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  String _messageFor(Object error) {
    if (error is DeviceFactorException) return error.toString();
    if (error is VaultUnlockException) return error.message;
    if (error is LifeVaultArchiveException) return error.message;
    if (error is VaultRecoveryException) return error.message;
    if (error is FormatException) return error.message;
    if (error is FileSystemException) {
      return '资料库文件读写失败，已有文件已保留。请检查存储空间与备份。';
    }
    if (kDebugMode) return error.toString();
    return '操作失败，请重试';
  }

  @override
  void dispose() {
    _disposed = true;
    for (final subscription in _agentSubscriptions) {
      unawaited(subscription.cancel());
    }
    _snapshotQuery.dispose();
    _agent.dispose();
    _agentSettings.dispose();
    _outboundConsent.dispose();
    _securityService?.dispose();
    recipient?.dispose();
    _speechService?.removeListener(notifyListeners);
    _speechService?.dispose();
    _session.dispose();
    super.dispose();
  }
}
