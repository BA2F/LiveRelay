import 'dart:io';
import 'dart:convert';

import 'package:archive/archive.dart';

import 'package:collection/collection.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../core/ai/ai_privacy.dart';
import 'card_summary.dart';
import 'device_capabilities.dart';
import '../core/domain/entities.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/biometric_key_store.dart';
import '../core/ports/ocr_provider.dart';
import '../core/ports/vault_repository.dart';
import '../core/security/chinese_passphrase.dart';
import '../core/security/vault_key_manager.dart';
import '../infrastructure/backup/life_vault_archive.dart';
import '../infrastructure/ai/ai_provider_settings_store.dart';
import '../infrastructure/ai/openai_compatible_provider.dart';
import '../infrastructure/blob/encrypted_blob_store.dart';
import '../infrastructure/import/edge_password_csv_importer.dart';
import '../infrastructure/ocr/google_mlkit_ocr_provider.dart';
import '../infrastructure/persistence/app_database.dart';
import '../infrastructure/persistence/sqlite_vault_repository.dart';
import '../infrastructure/security/android_biometric_key_store.dart';

enum VaultSessionState { loading, needsSetup, locked, unlocked, failure }

class AppController extends ChangeNotifier {
  AppController([
    this._applicationDirectory,
    BiometricKeyStore? biometricKeyStore,
    OcrProvider? ocrProvider,
    AiProvider? aiProvider,
    AiProviderSettingsStore? aiSettingsStore,
  ]) : _biometricKeyStore = biometricKeyStore ?? AndroidBiometricKeyStore(),
       _ocrProvider = ocrProvider ?? GoogleMlKitOcrProvider(),
       _aiProvider = aiProvider ?? OpenAiCompatibleProvider(),
       _aiSettingsStore = aiSettingsStore ?? AiProviderSettingsStore();

  final Directory? _applicationDirectory;
  final BiometricKeyStore _biometricKeyStore;
  final OcrProvider _ocrProvider;
  final AiProvider _aiProvider;
  final AiProviderSettingsStore _aiSettingsStore;
  final AiPrivacyProcessor _aiPrivacy = const AiPrivacyProcessor();
  final LifeVaultArchiveService _archiveService = LifeVaultArchiveService();
  final EdgePasswordCsvImporter _edgeImporter = const EdgePasswordCsvImporter();
  final EncryptedBlobStore _blobStore = EncryptedBlobStore();

  late final Directory _vaultDirectory;
  late final VaultKeyManager _keyManager;
  late final ChinesePassphraseCodec _passphraseCodec;
  VaultRepository? _repository;
  Uint8List? _sessionKey;

  VaultSessionState sessionState = VaultSessionState.loading;
  VaultHeaderMetadata? header;
  bool isBusy = false;
  bool biometricAvailable = false;
  AiProviderSettings aiSettings = const AiProviderSettings(
    endpoint: '',
    model: '',
    hasApiKey: false,
  );
  String? lastError;

  List<LifeCard> cards = const [];
  List<LifeCard> recycledCards = const [];
  List<CredentialEntry> recycledCredentials = const [];
  DateTime? lastBackupExport;
  List<VaultBlob> blobs = const [];
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
  final capabilities = DeviceCapabilities.current();

  FeatureCapability capability(AppFeature feature) =>
      capabilities.feature(feature, biometricAvailable: biometricAvailable);

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
      // Android's document picker materializes selected content in the app
      // cache. It must never survive as an unencrypted second copy.
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object {
        // Some desktop implementations do not expose cache cleanup. A failed
        // best-effort cleanup must not make an otherwise healthy Vault unusable.
      }
      await _clearKnownPlaintextCache();
      try {
        aiSettings = await _aiSettingsStore.read();
      } on Object {
        aiSettings = const AiProviderSettings(
          endpoint: '',
          model: '',
          hasApiKey: false,
        );
      }
      final support =
          _applicationDirectory ?? await getApplicationSupportDirectory();
      _vaultDirectory = Directory('${support.path}/live_relay/vault');
      _keyManager = VaultKeyManager(_vaultDirectory);
      final wordlist = await rootBundle.loadString(
        'assets/wordlists/new-default-pinyin.wordlist',
      );
      _passphraseCodec = ChinesePassphraseCodec.parse(wordlist);
      header = await _keyManager.readMetadata();
      try {
        biometricAvailable = await _biometricKeyStore.isAvailable();
      } on Object {
        biometricAvailable = false;
      }
      sessionState = header == null
          ? VaultSessionState.needsSetup
          : VaultSessionState.locked;
    } on Object catch (error) {
      lastError = _messageFor(error);
      sessionState = VaultSessionState.failure;
    }
    notifyListeners();
  }

  Future<void> _clearKnownPlaintextCache() async {
    try {
      final cache = await getTemporaryDirectory();
      if (!await cache.exists()) return;
      const mediaExtensions = <String>{
        '.jpg',
        '.jpeg',
        '.png',
        '.webp',
        '.heic',
        '.mp3',
        '.m4a',
        '.wav',
        '.aac',
        '.mp4',
        '.mov',
        '.webm',
      };
      await for (final entity in cache.list(recursive: true)) {
        if (entity is! File) continue;
        final name = path.basename(entity.path).toLowerCase();
        final isKnownTemporary =
            name.startsWith('ocr-') ||
            name.startsWith('recording-') ||
            name.startsWith('view-') ||
            mediaExtensions.contains(path.extension(name));
        if (isKnownTemporary) await entity.delete();
      }
    } on Object {
      // Cache is outside the authenticated Vault. Cleanup is retried on every
      // start and failure must not turn into data loss or an unlock failure.
    }
  }

  ChinesePassphrase generatePassphrase({int count = 6}) =>
      _passphraseCodec.generate(count: count);

  Future<void> setupVault({
    required String password,
    required bool usesChinesePassphrase,
    int? wordCount,
    bool enableBiometric = false,
  }) async {
    await _run(() async {
      final canonical = usesChinesePassphrase
          ? _passphraseCodec.canonicalize(password, wordCount: wordCount ?? 6)
          : password;
      final key = await _keyManager.create(
        canonicalPassword: canonical,
        passwordKind: usesChinesePassphrase ? 'diceware-cn-v1' : 'custom',
        wordCount: usesChinesePassphrase ? wordCount : null,
      );
      try {
        await _openWithKey(key);
        if (enableBiometric && biometricAvailable) {
          await _biometricKeyStore.saveMasterKey(key);
          await _keyManager.setBiometricEnabled(true);
        }
      } finally {
        _wipe(key);
      }
      header = await _keyManager.readMetadata();
      sessionState = VaultSessionState.unlocked;
      await _refreshUnlockedData();
    });
  }

  Future<void> unlockWithPassword(String password) async {
    await _run(() async {
      final metadata = header ?? await _keyManager.readMetadata();
      if (metadata == null) throw StateError('加密资料库尚未创建');
      final canonical = metadata.usesChinesePassphrase
          ? _passphraseCodec.canonicalize(
              password,
              wordCount: metadata.wordCount ?? 6,
            )
          : password;
      final key = await _keyManager.unlock(canonical);
      try {
        await _openWithKey(key);
      } finally {
        _wipe(key);
      }
      sessionState = VaultSessionState.unlocked;
      await _refreshUnlockedData();
    });
  }

  Future<void> unlockWithBiometric() async {
    await _run(() async {
      final key = await _biometricKeyStore.readMasterKey();
      if (key == null) throw StateError('设备中没有可用的指纹密钥槽');
      try {
        await _openWithKey(key);
      } finally {
        _wipe(key);
      }
      sessionState = VaultSessionState.unlocked;
      await _refreshUnlockedData();
    });
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (!isUnlocked) throw StateError('请先解锁加密资料库');
    if (enabled) {
      throw UnsupportedError('启用指纹需要重新输入主密码');
    }
    await _run(() async {
      await _biometricKeyStore.clear();
      await _keyManager.setBiometricEnabled(false);
      header = await _keyManager.readMetadata();
    });
  }

  Future<void> enableBiometricWithPassword(String password) async {
    if (!biometricAvailable) throw StateError('当前设备没有可用的强生物识别');
    await _run(() async {
      final metadata = header!;
      final canonical = metadata.usesChinesePassphrase
          ? _passphraseCodec.canonicalize(
              password,
              wordCount: metadata.wordCount ?? 6,
            )
          : password;
      final key = await _keyManager.unlock(canonical);
      try {
        await _biometricKeyStore.saveMasterKey(key);
        await _keyManager.setBiometricEnabled(true);
      } finally {
        _wipe(key);
      }
      header = await _keyManager.readMetadata();
    });
  }

  Future<Uint8List> exportVault(String password) async {
    if (!isUnlocked) throw StateError('请先解锁加密资料库');
    late Uint8List result;
    await _run(() async {
      final metadata = header ?? await _keyManager.readMetadata();
      if (metadata == null) throw StateError('加密资料库尚未创建');
      final key = await _keyManager.unlock(
        _canonicalizePassword(password, metadata),
      );
      final repository = _repository;
      _repository = null;
      try {
        if (repository != null) await repository.close();
        result = await _archiveService.create(
          vaultDirectory: _vaultDirectory,
          masterKey: key,
        );
      } finally {
        try {
          await _openWithKey(key);
          await _refreshUnlockedData();
        } finally {
          _wipe(key);
        }
      }
    });
    return result;
  }

  Future<void> restoreVault(Uint8List bytes, String backupPassword) async {
    await _run(() async {
      StagedLifeVault? staged;
      Uint8List? importedKey;
      try {
        await _vaultDirectory.parent.create(recursive: true);
        staged = await _archiveService.stage(
          archiveBytes: bytes,
          stagingParent: _vaultDirectory.parent,
        );
        final stagedKeyManager = VaultKeyManager(staged.directory);
        final metadata = await stagedKeyManager.readMetadata();
        if (metadata == null) {
          throw const LifeVaultArchiveException('.lvault 缺少 Vault header');
        }
        importedKey = await stagedKeyManager.unlock(
          _canonicalizePassword(backupPassword, metadata),
        );
        await _archiveService.verifyAuthentication(
          staged: staged,
          masterKey: importedKey,
        );
        await stagedKeyManager.setBiometricEnabled(false);
        final testDatabase = await AppDatabase.openEncrypted(
          vaultDirectory: staged.directory,
          masterKey: importedKey,
        );
        await testDatabase.close();

        final repository = _repository;
        _repository = null;
        if (repository != null) await repository.close();
        final rollback = Directory(
          '${_vaultDirectory.path}.rollback-'
          '${DateTime.now().microsecondsSinceEpoch}',
        );
        final hadVault = await _vaultDirectory.exists();
        var movedOriginal = false;
        try {
          if (hadVault) {
            await _vaultDirectory.rename(rollback.path);
            movedOriginal = true;
          }
          await staged.directory.rename(_vaultDirectory.path);
          staged = null;
          await _openWithKey(importedKey);
          header = await _keyManager.readMetadata();
          sessionState = VaultSessionState.unlocked;
          await _refreshUnlockedData();
          try {
            await _biometricKeyStore.clear();
          } on Object {
            // Imported headers disable biometrics; stale device slots are never used.
          }
          if (hadVault) {
            try {
              await rollback.delete(recursive: true);
            } on Object {
              // A cleanup failure must not roll back a completed import.
              // The remaining rollback is encrypted and outside the active vault.
            }
          }
        } on Object {
          await _repository?.close();
          _repository = null;
          if ((!hadVault || movedOriginal) && await _vaultDirectory.exists()) {
            await _vaultDirectory.delete(recursive: true);
          }
          if (movedOriginal) await rollback.rename(_vaultDirectory.path);
          header = await _keyManager.readMetadata();
          sessionState = header == null
              ? VaultSessionState.needsSetup
              : VaultSessionState.locked;
          _clearUnlockedData();
          _clearSessionKey();
          throw const LifeVaultArchiveException('恢复失败；原 Vault 已保留，请重新解锁');
        }
      } finally {
        if (staged != null && await staged.directory.exists()) {
          await staged.directory.delete(recursive: true);
        }
        if (importedKey != null) _wipe(importedKey);
        bytes.fillRange(0, bytes.length, 0);
      }
    });
  }

  Future<void> lock() async {
    final repository = _repository;
    _repository = null;
    if (repository != null) await repository.close();
    _clearUnlockedData();
    sessionState = VaultSessionState.locked;
    _clearSessionKey();
    notifyListeners();
  }

  void _clearUnlockedData() {
    cards = const [];
    recycledCards = const [];
    recycledCredentials = const [];
    lastBackupExport = null;
    blobs = const [];
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
      await _vaultDirectory.parent.create(recursive: true);
      final staged = await _archiveService.stage(
        archiveBytes: bytes,
        stagingParent: _vaultDirectory.parent,
      );
      Uint8List? key;
      AppDatabase? db;
      try {
        final manager = VaultKeyManager(staged.directory);
        final metadata = await manager.readMetadata();
        if (metadata == null) throw const LifeVaultArchiveException('备份缺少资料库头');
        key = await manager.unlock(_canonicalizePassword(password, metadata));
        await _archiveService.verifyAuthentication(
          staged: staged,
          masterKey: key,
        );
        db = await AppDatabase.openEncrypted(
          vaultDirectory: staged.directory,
          masterKey: key,
        );
        final r = SqliteVaultRepository(db);
        final archive = ZipDecoder().decodeBytes(bytes);
        final container = jsonDecode(
          utf8.decode(archive.findFile('container.json')!.readBytes()!),
        ) as Map;
        preview = BackupPreview(
          createdAt: DateTime.tryParse('${container['createdAt']}'),
          cards: (await r.listCards()).length,
          credentials: (await r.listCredentials()).length,
          originals: (await r.listBlobs()).length,
          recycledCards: (await r.listCards(recycled: true)).length,
          recycledCredentials: (await r.listCredentials(recycled: true)).length,
        );
      } finally {
        await db?.close();
        if (key != null) _wipe(key);
        if (await staged.directory.exists()) {
          await staged.directory.delete(recursive: true);
        }
      }
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
  Future<LifeCard?> getCard(String id) => _requireRepository().getCard(id);
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
        final key = _requireSessionKey();
        final blob = await _blobStore.write(
          vaultDirectory: _vaultDirectory,
          masterKey: key,
          clearBytes: bytes,
          originalName: originalName,
          mimeType: mimeType,
          mediaKind: mediaKind,
        );
        try {
          card = await _requireRepository().registerBlob(blob);
        } on Object {
          await _blobStore.delete(vaultDirectory: _vaultDirectory, blob: blob);
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
    return _blobStore.read(
      vaultDirectory: _vaultDirectory,
      masterKey: _requireSessionKey(),
      blob: blob,
    );
  }

  Future<LifeCard> runOcr(String blobId) async {
    late LifeCard card;
    await _run(() async {
      final blob = blobs.firstWhereOrNull((item) => item.id == blobId);
      if (blob == null) throw StateError('原始资料不存在');
      if (blob.mediaKind != BlobMediaKind.image) {
        throw const FormatException('只有图片原件可以执行 OCR');
      }
      final bytes = await _blobStore.read(
        vaultDirectory: _vaultDirectory,
        masterKey: _requireSessionKey(),
        blob: blob,
      );
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
  }) async {
    await _run(() async {
      await _aiSettingsStore.save(
        endpoint: endpoint,
        model: model,
        apiKey: apiKey,
      );
      aiSettings = await _aiSettingsStore.read();
    });
  }

  Future<void> clearAiSettings() async {
    await _run(() async {
      await _aiSettingsStore.clear();
      aiSettings = const AiProviderSettings(
        endpoint: '',
        model: '',
        hasApiKey: false,
      );
    });
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

  Future<void> _openWithKey(Uint8List key) async {
    await _repository?.close();
    final database = await AppDatabase.openEncrypted(
      vaultDirectory: _vaultDirectory,
      masterKey: key,
    );
    _repository = SqliteVaultRepository(database);
    _replaceSessionKey(key);
  }

  String _canonicalizePassword(String password, VaultHeaderMetadata metadata) {
    return metadata.usesChinesePassphrase
        ? _passphraseCodec.canonicalize(
            password,
            wordCount: metadata.wordCount ?? 6,
          )
        : password;
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
    blobs = results[1] as List<VaultBlob>;
    credentials = results[2] as List<CredentialEntry>;
    releasePolicies = results[3] as List<ReleasePolicy>;
    lifeStateHistory = results[4] as List<LifeStateEvent>;
    lifeState = results[5] as LifeState;
    insights = results[6] as VaultInsights;
    recycledCards = results[7] as List<LifeCard>;
    recycledCredentials = results[8] as List<CredentialEntry>;
    lastBackupExport = await repository.lastBackupExport();
  }

  Future<void> _mutate(
    Future<Object?> Function(VaultRepository repository) action,
  ) {
    return _run(() async {
      await action(_requireRepository());
      await _refreshUnlockedData();
    });
  }

  VaultRepository _requireRepository() {
    final repository = _repository;
    if (repository == null) throw StateError('加密资料库尚未解锁');
    return repository;
  }

  Uint8List _requireSessionKey() {
    final key = _sessionKey;
    if (key == null) throw StateError('加密资料库尚未解锁');
    return key;
  }

  void _replaceSessionKey(Uint8List key) {
    _clearSessionKey();
    _sessionKey = Uint8List.fromList(key);
  }

  void _clearSessionKey() {
    final key = _sessionKey;
    if (key != null) _wipe(key);
    _sessionKey = null;
  }

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
    if (error is VaultUnlockException) return error.message;
    if (error is LifeVaultArchiveException) return error.message;
    if (error is FormatException) return error.message;
    if (kDebugMode) return error.toString();
    return '操作失败，请重试';
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  @override
  void dispose() {
    _repository?.close();
    _clearSessionKey();
    super.dispose();
  }
}
