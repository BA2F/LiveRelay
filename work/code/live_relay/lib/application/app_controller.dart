import 'dart:io' show FileSystemException;
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

import 'vault_session.dart';
import 'local_handoff_service.dart';
import 'recipient_service.dart';
import 'vault_security_service.dart';
import '../core/security/recovery_credential.dart';
import 'draft_agent_service.dart';
import 'speech_service.dart';
import 'vault_backup_service.dart';

import '../core/ai/ai_privacy.dart';
import 'card_summary.dart';
import 'workbench/card_references.dart';
import 'device_capabilities.dart';
import '../core/domain/entities.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/ai_conversation_provider.dart';
import '../core/ports/device_factor_protection.dart';
import '../core/ports/ocr_provider.dart';
import '../core/ports/vault_repository.dart';
import '../core/security/chinese_passphrase.dart';
import '../infrastructure/backup/life_vault_archive.dart'
    show LifeVaultArchiveException;
import '../infrastructure/backup/vault_restore_transaction.dart'
    show VaultRecoveryException;
import '../core/security/vault_key_manager.dart';
import '../infrastructure/ai/ai_provider_settings_store.dart';
import '../infrastructure/import/edge_password_csv_importer.dart';

export 'vault_session.dart' show VaultSessionState;

class AppController extends ChangeNotifier {
  AppController({
    required this._session,
    required this._backup,
    required this._ocrProvider,
    required this._aiProvider,
    required this._aiSettingsStore,
    required this._edgeImporter,
    required this._prepareEnvironment,
    this._draftAgentService,
    this._speechService,
    this._securityService,
    this.handoff,
    this.recipient,
  }) {
    _speechService?.addListener(notifyListeners);
    _securityService?.addListener(notifyListeners);
  }

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
  final RecipientService? recipient;
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
  final DraftAgentService? _draftAgentService;
  final SpeechService? _speechService;
  SpeechService? get speech => _speechService;
  final VaultSession _session;
  final VaultBackupService _backup;
  final OcrProvider _ocrProvider;
  final AiProvider _aiProvider;
  final AiProviderSettingsStore _aiSettingsStore;
  final EdgePasswordCsvImporter _edgeImporter;
  final Future<void> Function() _prepareEnvironment;
  final AiPrivacyProcessor _aiPrivacy = const AiPrivacyProcessor();

  VaultSessionState get sessionState => _session.state;
  VaultHeaderMetadata? get header => _session.header;
  bool get biometricAvailable => _session.biometricAvailable;
  AiCancellation? _agentCancellation;
  void cancelAgentTask() => _agentCancellation?.cancel();
  final exitCleanups = <Future<void> Function()>{};
  bool isBusy = false;
  bool agentCommandsAvailable = false;
  AiProviderSettings aiSettings = const AiProviderSettings(
    endpoint: '',
    model: '',
    hasApiKey: false,
  );
  List<AiProviderSettings> aiProfiles = const [];
  int aiConfigurationGeneration = 0;
  String? lastError;
  String? get recoveryNotice => _backup.recoveryNotice;

  List<LifeCard> cards = const [];
  List<CardReference> cardReferences = const [];
  Future<void> setCardReferences(String from, List<String> targets) =>
      _mutate((r) => CardReferenceStore(r).replace(from, targets));
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

  bool get isUnlocked => sessionState == VaultSessionState.unlocked;
  DeviceCapabilities capabilities = DeviceCapabilities.current();
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
      try {
        aiSettings = await _aiSettingsStore.read();
        aiProfiles = await _aiSettingsStore.readProfiles();
      } on Object {
        aiSettings = const AiProviderSettings(
          endpoint: '',
          model: '',
          hasApiKey: false,
        );
      }
      try {
        await _speechService?.refresh();
        agentCommandsAvailable =
            await _draftAgentService?.commandAvailable() ?? false;
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
      _mutate((r) => r.recordBackupExport(DateTime.now()));

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
  }) => _mutate(
    (repository) => repository.createCard(
      draft,
      sourceKind: sourceKind,
      sourceLabel: sourceLabel,
    ),
  );

  Future<void> updateCard(
    String id,
    CardDraft draft, {
    String changeNote = '更新卡片',
  }) => _mutate(
    (repository) => repository.updateCard(id, draft, changeNote: changeNote),
  );

  Future<void> confirmCard(String id) =>
      _mutate((repository) => repository.confirmCard(id));

  Future<void> splitCard(String id, List<CardDraft> parts) =>
      _mutate((repository) => repository.splitCard(id, parts));

  Future<void> combineCards(String title, List<String> memberIds) =>
      _mutate((repository) => repository.combineCards(title, memberIds));

  Future<void> restoreCard(String id) => _mutate((r) => r.restoreCard(id));
  Future<void> restoreCredential(String id) =>
      _mutate((r) => r.restoreCredential(id));
  Future<List<LifeCard>> cardsForBlob(String blobId) =>
      _requireRepository().cardsForBlob(blobId);
  Future<List<CardSource>> cardSources(String id) =>
      _requireRepository().cardSources(id);
  Future<List<CardSource>> currentCardSources(String id) =>
      _requireRepository().currentCardSources(id);
  Future<void> setCardOriginals(String id, List<String> blobIds) =>
      _mutate((r) => r.setCardOriginals(id, blobIds));
  Future<void> restoreCardRevision(String id, int number) =>
      _mutate((r) => r.restoreCardRevision(id, number));
  Future<CardDeletionPreview> previewCardDeletion(List<String> ids) =>
      _requireRepository().previewCardDeletion(ids);
  Future<void> trashCards(
    List<String> ids, {
    bool recycleUnsharedOriginals = false,
  }) => _mutate(
    (r) =>
        r.trashCards(ids, recycleUnsharedOriginals: recycleUnsharedOriginals),
  );
  Future<void> restoreOriginal(String id) =>
      _mutate((r) => r.restoreOriginal(id));
  Future<LifeCard?> getCard(String id) => _requireRepository().getCard(id);
  Future<String?> readWorkbenchState() =>
      _requireRepository().readLocalValue('desktop.workbench.v1');
  Future<void> writeWorkbenchState(String value) =>
      _requireRepository().writeLocalValue('desktop.workbench.v1', value);
  Future<String?> readWorkbenchExtensions() =>
      _requireRepository().readLocalValue('workbench.extensions.v1');
  Future<void> writeWorkbenchExtensions(String value) =>
      _requireRepository().writeLocalValue('workbench.extensions.v1', value);
  Future<void> createCardFromOriginal(String blobId, CardDraft draft) =>
      _mutate((r) => r.createCardFromOriginal(blobId, draft));

  Future<void> trashCard(String id) =>
      _mutate((repository) => repository.trashCard(id));

  Future<LifeCard> importOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async {
    late LifeCard card;
    await _run(() async {
      try {
        final blob = await _session.writeOriginal(
          bytes: bytes,
          originalName: originalName,
          mimeType: mimeType,
          mediaKind: mediaKind,
        );
        try {
          card = await _requireRepository().registerBlob(blob);
        } on Object {
          await _session.deleteOriginal(blob);
          rethrow;
        }
        await _refreshUnlockedData();
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
    return card;
  }

  Future<Uint8List> readOriginal(String blobId) async {
    final blob = blobs.where((item) => item.id == blobId).firstOrNull;
    if (blob == null) throw StateError('原始资料不存在');
    return _session.readOriginal(blob);
  }

  Future<LifeCard> runOcr(String blobId) async {
    late LifeCard card;
    await _run(() async {
      final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
      if (blob == null) throw StateError('原始资料不存在');
      if (blob.mediaKind != BlobMediaKind.image) {
        throw const FormatException('只有图片原件可以执行 OCR');
      }
      final bytes = await _session.readOriginal(blob);
      late OcrResult result;
      try {
        result = await _ocrProvider.recognize(
          imageBytes: bytes,
          originalName: blob.originalName,
        );
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
      card = await _requireRepository().saveOcrResult(blob.id, result);
      await _refreshUnlockedData();
    });
    return card;
  }

  Future<void> saveSensitiveMarks(String blobId, List<SensitiveMark> marks) =>
      _mutate((repository) => repository.saveSensitiveMarks(blobId, marks));

  String previewAiDisclosure(String blobId, List<SensitiveMark> marks) {
    final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
    if (blob == null) throw StateError('原始资料不存在');
    return _aiPrivacy.tokenize(lines: blob.ocrLines, marks: marks).redactedText;
  }

  Future<int> organizeWithAi(String blobId, List<SensitiveMark> marks) async {
    var count = 0;
    await _run(() async {
      final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
      if (blob == null) throw StateError('原始资料不存在');
      if (!aiSettings.isConfigured) {
        throw StateError('请先配置 AI 服务');
      }
      await _requireRepository().saveSensitiveMarks(blobId, marks);
      final payload = _aiPrivacy.tokenize(lines: blob.ocrLines, marks: marks);
      final apiKey = await _aiSettingsStore.readApiKey();
      if (apiKey == null || apiKey.isEmpty) {
        throw StateError('AI 服务密钥不存在');
      }
      final response = await _aiProvider.organize(
        AiProviderRequest(
          endpoint: Uri.parse(aiSettings.endpoint),
          apiKey: apiKey,
          model: aiSettings.model,
          redactedText: payload.redactedText,
          protocol: aiSettings.protocol,
        ),
      );
      final suggestions = _aiPrivacy.validateAndRehydrate(response, payload);
      final cards = await _requireRepository().saveAiSuggestions(
        blobId,
        suggestions.map((item) => item.toDraft()).toList(growable: false),
        providerLabel:
            '获授权云 AI · ${aiSettings.model} · ${Uri.parse(aiSettings.endpoint).host}',
      );
      count = cards.length;
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
    String? profileId,
    String? name,
    List<String>? models,
    bool create = false,
  }) async {
    await _run(() async {
      aiConfigurationGeneration++;
      if (name != null) {
        await _aiSettingsStore.saveProfile(
          id: profileId,
          create: create,
          name: name,
          endpoint: endpoint,
          model: model,
          models: models ?? [model],
          protocol: protocol ?? aiSettings.protocol,
          images: supportsImages ?? false,
          files: supportsFiles ?? false,
          apiKey: apiKey,
        );
      } else {
        await _aiSettingsStore.save(
          endpoint: endpoint,
          model: model,
          apiKey: apiKey,
        );
        if (protocol != null) await _aiSettingsStore.saveProtocol(protocol);
        if (supportsImages != null || supportsFiles != null) {
          await _aiSettingsStore.saveCapabilities(
            images: supportsImages ?? aiSettings.supportsImages,
            files: supportsFiles ?? aiSettings.supportsFiles,
          );
        }
      }
      aiSettings = await _aiSettingsStore.read();
      aiProfiles = await _aiSettingsStore.readProfiles();
    });
  }

  Future<void> selectAiProfile(String id, String model) => _run(() async {
    aiConfigurationGeneration++;
    await _aiSettingsStore.select(id, model);
    aiSettings = await _aiSettingsStore.read();
    aiProfiles = await _aiSettingsStore.readProfiles();
  });
  Future<void> removeAiProfile(String id) => _run(() async {
    aiConfigurationGeneration++;
    await _aiSettingsStore.remove(id);
    aiSettings = await _aiSettingsStore.read();
    aiProfiles = await _aiSettingsStore.readProfiles();
  });

  Future<void> clearAiSettings() async {
    await _run(() async {
      await _aiSettingsStore.clear();
      aiConfigurationGeneration++;
      aiProfiles = const [];
      aiSettings = const AiProviderSettings(
        endpoint: '',
        model: '',
        hasApiKey: false,
      );
    });
  }

  String previewAgentDisclosure(String text, List<SensitiveMark> marks) =>
      (_draftAgentService ?? (throw StateError('Agent 尚未配置')))
          .prepare(text, marks)
          .redactedText;

  Future<AgentDraftBatch> proposeAgentDrafts(
    String text,
    List<SensitiveMark> marks, {
    bool allowCommands = false,
  }) async {
    late AgentDraftBatch batch;
    await _run(() async {
      if (!isUnlocked) throw StateError('请先解锁资料库');
      if (!aiSettings.isConfigured ||
          aiSettings.protocol != AiProtocol.responses) {
        throw StateError('请在 AI 服务设置中选择 Responses 并配置服务');
      }
      final cancellation = AiCancellation();
      _agentCancellation = cancellation;
      try {
        final key = await _aiSettingsStore.readApiKey();
        cancellation.check();
        if (!isUnlocked) throw StateError('资料库已锁定');
        if (key == null || key.isEmpty) throw StateError('AI 服务密钥不存在');
        batch = await _draftAgentService!.propose(
          text: text,
          marks: marks,
          endpoint: Uri.parse(aiSettings.endpoint),
          model: aiSettings.model,
          apiKey: key,
          cancellation: cancellation,
          allowCommands: allowCommands,
        );
      } finally {
        if (identical(_agentCancellation, cancellation)) {
          _agentCancellation = null;
        }
      }
      if (!isUnlocked) throw StateError('资料库已锁定，本次结果已丢弃');
    });
    return batch;
  }

  AiTokenizedPayload prepareConversationText(
    String text,
    List<SensitiveMark> marks,
  ) => (_draftAgentService ?? (throw StateError('Agent 尚未配置'))).prepare(
    text,
    marks,
  );
  Future<String?> readConversationState() =>
      _requireRepository().readChunkedLocalValue('agent.conversation.v1');
  Future<void> writeConversationState(String value) => _requireRepository()
      .writeChunkedLocalValue('agent.conversation.v1', value);
  Future<AiConversationResponse> converse(
    String text,
    List<Map<String, Object?>> history, {
    List<Map<String, Object?>>? inputContent,
  }) async {
    late AiConversationResponse response;
    await _run(() async {
      if (!isUnlocked) throw StateError('请先解锁资料库');
      if (!aiSettings.isConfigured) {
        throw const FormatException('请先配置 AI 服务；也可以在我的资料中手动新建卡片');
      }
      final provider = _aiProvider;
      if (provider is! AiConversationProvider) {
        throw const FormatException('此 AI 服务尚未支持持续对话');
      }
      final cancellation = AiCancellation();
      _agentCancellation = cancellation;
      try {
        final key = await _aiSettingsStore.readApiKey();
        cancellation.check();
        if (!isUnlocked || key == null || key.isEmpty) {
          throw const FormatException('服务密钥不存在或资料库已锁定');
        }
        response = await (provider as AiConversationProvider).converse(
          AiProviderRequest(
            endpoint: Uri.parse(aiSettings.endpoint),
            model: aiSettings.model,
            apiKey: key,
            protocol: aiSettings.protocol,
            redactedText: text,
            inputContent: inputContent,
            cancellation: cancellation,
          ),
          history,
        );
        cancellation.check();
        if (!isUnlocked) throw const FormatException('资料库已锁定，本次结果已丢弃');
      } finally {
        if (identical(_agentCancellation, cancellation)) {
          _agentCancellation = null;
        }
      }
    });
    return response;
  }

  Future<void> acceptConversationCards(
    String reviewId,
    String sourceText,
    List<AiCardSuggestion> suggestions, {
    required String providerLabel,
    List<String> originalIds = const [],
  }) => _mutate(
    (r) => r.saveReviewedAgentSuggestions(
      reviewId,
      sourceText,
      suggestions
          .map(
            (s) => CardDraft(
              title: s.title,
              content: s.content,
              kind: s.kind,
              status: CardStatus.confirmed,
              tags: ['AI', if (s.isInference) '推断', ...s.tags],
            ),
          )
          .toList(),
      providerLabel: providerLabel,
      originalIds: originalIds,
    ),
  );

  Future<void> saveAgentDrafts(AgentDraftBatch batch) => _mutate(
    (repository) => repository.saveAgentSuggestions(
      batch.sourceText,
      batch.suggestions.map((s) => s.toDraft()).toList(),
      providerLabel: batch.providerLabel,
    ),
  );

  Future<void> saveSpeechDraft(String text, {String? blobId}) {
    final content = text.trim();
    if (content.isEmpty || content.length > 32000) {
      throw const FormatException('语音文字为空或过长');
    }
    final draft = CardDraft(
      title: String.fromCharCodes(content.split('\n').first.runes.take(28)),
      content: content,
      kind: CardKind.note,
      status: CardStatus.draft,
      tags: ['语音', '待确认'],
    );
    if (blobId != null) {
      return _mutate(
        (r) => r.createCardFromOriginal(
          blobId,
          draft,
          sourceKind: SourceKind.audio,
          sourceLabel: '本地语音识别 · 本人校对',
        ),
      );
    }
    return createCard(
      draft,
      sourceKind: SourceKind.ownerInput,
      sourceLabel: '语音页手动输入 · 本人校对',
    );
  }

  Future<List<CardRevision>> cardHistory(String id) =>
      _requireRepository().cardHistory(id);

  Future<List<CardRelation>> cardRelations(String id) =>
      _requireRepository().relationsForCard(id);

  Future<void> saveCredential(CredentialDraft draft, {String? id}) =>
      _mutate((repository) => repository.saveCredential(draft, id: id));

  Future<void> trashCredential(String id) =>
      _mutate((repository) => repository.trashCredential(id));

  Future<void> purgeCredential(String id) =>
      _mutate((repository) => repository.purgeCredential(id));

  Future<EdgePasswordImportResult> importEdgePasswords(Uint8List bytes) async {
    try {
      final parsed = _edgeImporter.parse(bytes);
      await _mutate(
        (repository) => repository.importCredentials(parsed.entries),
      );
      return parsed;
    } finally {
      _wipe(bytes);
    }
  }

  Future<List<CredentialRevision>> credentialHistory(String id) =>
      _requireRepository().credentialHistory(id);

  Future<ReleasePolicy> releasePolicy(String recordType, String recordId) =>
      _requireRepository().getReleasePolicy(recordType, recordId);

  Future<void> saveReleasePolicy(ReleasePolicy policy) =>
      _mutate((repository) => repository.saveReleasePolicy(policy));

  Future<void> transitionLifeState(LifeState state, {required String reason}) =>
      _mutate(
        (repository) => repository.transitionLifeState(state, reason: reason),
      );

  Future<void> resetLifeStateSimulation() => _mutate(
    (repository) =>
        repository.resetLifeStateSimulation(reason: '用户明确重置 MVP 模拟'),
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
    final repository = _requireRepository();
    final results = await Future.wait<Object>([
      repository.listCards(),
      repository.listBlobs(),
      repository.listCredentials(),
      repository.listReleasePolicies(),
      repository.lifeStateHistory(),
      repository.currentLifeState(),
      repository.insights(),
      repository.listCards(recycled: true),
      repository.listCredentials(recycled: true),
    ]);
    cards = results[0] as List<LifeCard>;
    cardReferences = await CardReferenceStore(repository).read();
    blobs = results[1] as List<VaultBlob>;
    recycledBlobIds = (await repository.recycledOriginalIds()).toSet();
    credentials = results[2] as List<CredentialEntry>;
    releasePolicies = results[3] as List<ReleasePolicy>;
    lifeStateHistory = results[4] as List<LifeStateEvent>;
    lifeState = results[5] as LifeState;
    insights = results[6] as VaultInsights;
    recycledCards = results[7] as List<LifeCard>;
    recycledCredentials = results[8] as List<CredentialEntry>;
    lastBackupExport = await repository.lastBackupExport();
    if (handoff != null) {
      final raw = await repository.readLocalValue('identity.profile');
      ownerProfile = raw == null
          ? const {'name': '本人', 'contact': '', 'note': ''}
          : Map<String, Object?>.from(jsonDecode(raw) as Map);
    }
  }

  Future<void> _mutate(
    Future<Object?> Function(VaultRepository repository) action,
  ) {
    return _run(() async {
      await action(_requireRepository());
      await _refreshUnlockedData();
    });
  }

  VaultRepository _requireRepository() => _session.repository;

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

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  @override
  void dispose() {
    cancelAgentTask();
    _securityService?.removeListener(notifyListeners);
    _securityService?.dispose();
    recipient?.dispose();
    _speechService?.removeListener(notifyListeners);
    _speechService?.dispose();
    _session.dispose();
    super.dispose();
  }
}
