// Run directly with `dart run test/support/agent_service_headless_checks.dart`.
// These application checks import no Flutter, storage plugin or SQLite adapter.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_relay/application/agent/agent_review_service.dart';
import 'package:live_relay/application/vault_snapshot_query.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/core/ports/vault_originals.dart';
import 'package:live_relay/core/ports/ocr_provider.dart';
import 'package:live_relay/application/agent/agent_service.dart';
import 'package:live_relay/application/agent/agent_settings_service.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/ai/ai_provider_settings.dart';
import 'package:live_relay/core/ai/review_actions.dart';
import 'package:live_relay/core/ai/review_source.dart';
import 'package:live_relay/core/ai/reviewed_agent_plan.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/card_references.dart';
import 'package:live_relay/core/ports/ai_conversation_provider.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/ports/ai_settings_repository.dart';
import 'package:live_relay/core/ports/unlocked_vault.dart';
import 'package:live_relay/core/ports/vault_repository.dart';

void require(bool value, String message) {
  if (!value) throw StateError(message);
}

Future<void> rejects(Future<Object?> future, String message) async {
  Object? failure;
  try {
    await future;
  } on Object catch (error) {
    failure = error;
  }
  require(
    failure != null && failure.toString().contains(message),
    'Expected rejection containing $message; got $failure',
  );
}

Map<String, Future<void> Function()> agentServiceChecks() => {
  'headless conversation uses injected credentials and emits activity':
      () async {
        final fixture = await _Fixture.create();
        final events = <AgentActivity>[];
        final idle = Completer<void>();
        final subscription = fixture.agent.activity.listen((state) {
          events.add(state);
          if (state == AgentActivity.idle && !idle.isCompleted) idle.complete();
        });
        try {
          final result = fixture.agent.converse('approved public fixture', []);
          await fixture.provider.waitForRequests(1);
          final request = fixture.provider.requests.single;
          require(
            request.model == 'fixture-model' && request.apiKey == 'fixture-key',
            'Injected request lost configuration',
          );
          require(fixture.agent.isBusy, 'No pending network slot');
          fixture.provider.complete(0);
          await result;
          await idle.future;
          require(
            !fixture.agent.isBusy &&
                events.first == AgentActivity.waiting &&
                events.last == AgentActivity.idle,
            'Activity lifecycle changed',
          );
        } finally {
          await subscription.cancel();
          fixture.dispose();
        }
      },
  'activity observer can cancel a request without a reentrant stream error':
      () async {
        final fixture = await _Fixture.create();
        final key = Completer<String?>();
        fixture.store.pendingKey = key.future;
        final cancelled = Completer<void>();
        final subscription = fixture.agent.activity.listen((state) {
          if (state == AgentActivity.waiting) {
            fixture.agent.cancel();
            cancelled.complete();
          }
        });
        try {
          final rejected = rejects(
            fixture.agent.converse('approved fixture', []),
            '已取消',
          );
          await cancelled.future;
          key.complete('fixture-key');
          await rejected;
          require(
            fixture.provider.requests.isEmpty,
            'Cancelled request reached provider',
          );
        } finally {
          if (!key.isCompleted) key.complete(null);
          await subscription.cancel();
          fixture.dispose();
        }
      },
  'configuration changed during credential read prevents any upstream request':
      () async {
        final fixture = await _Fixture.create();
        final key = Completer<String?>();
        fixture.store.pendingKey = key.future;
        try {
          final pending = fixture.agent.converse('approved fixture', []);
          final rejected = rejects(pending, '配置已变化');
          await fixture.configuration.save(
            endpoint: 'https://fixture.invalid/new',
            model: 'new',
          );
          key.complete('fixture-key');
          await rejected;
          require(
            fixture.provider.requests.isEmpty,
            'Unapproved request reached provider',
          );
        } finally {
          if (!key.isCompleted) key.complete(null);
          fixture.dispose();
        }
      },
  'failed configuration write invalidates an already pending response':
      () async {
        final fixture = await _Fixture.create();
        try {
          final pending = fixture.agent.converse('approved fixture', []);
          final rejected = rejects(pending, '配置已变化');
          await fixture.provider.waitForRequests(1);
          fixture.store.rejectSave = true;
          await rejects(
            fixture.configuration.save(
              endpoint: 'https://fixture.invalid/new',
              model: 'new',
            ),
            'fixture write failed',
          );
          require(
            !fixture.configuration.settings.isConfigured,
            'Failed write retained a sendable stale configuration',
          );
          fixture.provider.complete(0);
          await rejected;
          await rejects(
            fixture.agent.converse('new request after failed save', []),
            '请先配置 AI 服务',
          );
          require(
            fixture.provider.requests.length == 1,
            'Failed configuration allowed a new upstream request',
          );
        } finally {
          fixture.dispose();
        }
      },
  'session replacement discards late replies without a Flutter lock callback':
      () async {
        final fixture = await _Fixture.create();
        try {
          final pending = fixture.agent.converse('approved fixture', []);
          final rejected = rejects(pending, '结果已丢弃');
          await fixture.provider.waitForRequests(1);
          fixture.vault.sessionGeneration++;
          fixture.vault.isUnlocked = true;
          fixture.provider.complete(0);
          await rejected;
        } finally {
          fixture.dispose();
        }
      },
  'cancelled request cannot release the slot of a newer request': () async {
    final fixture = await _Fixture.create();
    try {
      final first = fixture.agent.converse('first approved fixture', []);
      final rejected = rejects(first, '已取消');
      await fixture.provider.waitForRequests(1);
      await rejects(fixture.agent.converse('overlap', []), '等待当前操作');
      fixture.agent.cancel();
      final second = fixture.agent.converse('second approved fixture', []);
      await fixture.provider.waitForRequests(2);
      require(
        fixture.provider.requests.length == 2,
        'New request did not acquire slot',
      );
      fixture.provider.complete(0);
      await rejected;
      require(fixture.agent.isBusy, 'Old request cleared newer slot');
      fixture.provider.complete(1);
      await second;
      require(!fixture.agent.isBusy, 'Completed request retained slot');
    } finally {
      fixture.dispose();
    }
  },
  'configuration writes are gated in the use case without a UI busy flag':
      () async {
        final fixture = await _Fixture.create();
        final write = Completer<void>();
        fixture.store.pendingSave = write.future;
        try {
          final save = fixture.configuration.save(
            endpoint: 'https://fixture.invalid/new',
            model: 'new',
          );
          await rejects(fixture.configuration.clear(), '等待当前服务配置');
          await rejects(
            fixture.agent.converse('request during configuration write', []),
            '服务配置正在保存',
          );
          require(
            fixture.provider.requests.isEmpty,
            'Configuration write allowed an upstream request',
          );
          write.complete();
          await save;
          require(
            fixture.configuration.generation == 1 &&
                fixture.configuration.settings.model == 'new',
            'Concurrent change altered generation or settings',
          );
        } finally {
          if (!write.isCompleted) write.complete();
          fixture.dispose();
        }
      },
  'explicit review reaches one atomic repository operation with private defaults':
      () async {
        final fixture = await _Fixture.create();
        try {
          final review = AgentReviewService(fixture.vault);
          await review.accept('headless-review', 'approved source', const [
            AiCardSuggestion(
              title: 'public fixture',
              content: 'body',
              kind: CardKind.note,
              isInference: true,
              tags: ['fixture'],
            ),
          ], providerLabel: 'fixture-provider');
          require(
            fixture.vault.store.reviewWrites == 1,
            'Confirmation split into multiple writes',
          );
          final draft = fixture.vault.store.reviewDrafts.single;
          require(
            draft.status == CardStatus.confirmed && draft.tags.contains('推断'),
            'Owner confirmation lost status or provenance',
          );
          require(
            fixture.vault.store.reviewActions.isEmpty,
            'Confirmation invented a release plan',
          );
          final plans = await review.reviewedActions('headless-review');
          require(plans != null && plans.isEmpty, 'Stored review plan changed');
        } finally {
          fixture.dispose();
        }
      },
  'typed snapshot query runs without Flutter and rejects replaced sessions':
      () async {
        final vault = _SnapshotVault();
        final query = VaultSnapshotQuery(vault);
        final snapshot = await query.load();
        require(
          snapshot.cards.single.id == 'headless-card' &&
              snapshot.ownerProfile['name'] == '本人',
          'Snapshot projection changed',
        );
        var immutable = false;
        try {
          snapshot.cards.clear();
        } on UnsupportedError {
          immutable = true;
        }
        require(immutable, 'Snapshot collection is mutable');
        final gate = Completer<List<LifeCard>>();
        vault.store.pendingCards = gate.future;
        final rejected = rejects(query.load(), '查询已丢弃');
        vault.sessionGeneration++;
        gate.complete([_card('stale', CardKind.note)]);
        await rejected;
      },
  'confirmation plan freezes caller collections before transaction waiting':
      () async {
        final tags = ['original'];
        final references = ['reference'];
        final drafts = [
          CardDraft(title: 'fixture', content: 'body', tags: tags),
        ];
        final actions = [ReviewActions(referenceIds: references)];
        final plan = ReviewedAgentPlan(
          reviewId: 'immutable-review',
          sourceText: 'fixture',
          drafts: drafts,
          providerLabel: 'fixture',
          actions: actions,
        );
        tags.clear();
        references.clear();
        drafts.clear();
        actions.clear();
        require(
          plan.drafts.single.tags.single == 'original' &&
              plan.targetIds.single == 'reference',
          'Caller mutation changed an in-flight plan',
        );
        await rejects(Future<void>(() => plan.validateTargets({})), '引用卡片已失效');
      },
  'headless original registration failure compensates file and wipes input':
      () async {
        final vault = _ContentVault();
        vault.store.rejectRegistration = true;
        final bytes = Uint8List.fromList([1, 2, 3]);
        final content = VaultContentService(vault: vault, ocr: _FailingOcr());
        await rejects(
          content.importOriginal(
            bytes: bytes,
            originalName: 'public.png',
            mimeType: 'image/png',
            mediaKind: BlobMediaKind.image,
          ),
          'fixture register failed',
        );
        require(
          vault.deleted && bytes.every((b) => b == 0),
          'Registration failure did not compensate and wipe',
        );
      },
  'headless OCR failure wipes bytes and session replacement discards clear original':
      () async {
        final vault = _ContentVault();
        final content = VaultContentService(vault: vault, ocr: _FailingOcr());
        await rejects(content.runOcr('original'), 'fixture OCR failed');
        require(
          vault.clearBytes.every((b) => b == 0),
          'OCR failure retained clear bytes',
        );
        vault.clearBytes = Uint8List.fromList([4, 5, 6]);
        vault.readStarted = false;
        final read = Completer<Uint8List>();
        vault.pendingRead = read.future;
        final pending = content.readOriginal('original');
        final rejected = rejects(pending, '结果已丢弃');
        for (var i = 0; i < 100 && !vault.readStarted; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        require(vault.readStarted, 'Original read never entered');
        vault.sessionGeneration++;
        read.complete(vault.clearBytes);
        await rejected;
        require(
          vault.clearBytes.every((b) => b == 0),
          'Late original retained clear bytes',
        );
      },
  'headless CSV import preserves exact secret and wipes both success and failure input':
      () async {
        final vault = _ContentVault();
        final content = VaultContentService(vault: vault, ocr: _FailingOcr());
        final invalid = Uint8List.fromList(utf8.encode('invalid,csv'));
        await rejects(content.importEdgePasswords(invalid), '需要');
        require(
          invalid.every((b) => b == 0),
          'Invalid CSV retained source bytes',
        );
        final valid = Uint8List.fromList(
          utf8.encode(
            'name,url,username,password\npublic,https://fixture.invalid,user,"  public secret  "\n',
          ),
        );
        await content.importEdgePasswords(valid);
        require(
          valid.every((b) => b == 0) &&
              vault.store.imported.single.secret == '  public secret  ',
          'CSV changed secret or retained bytes',
        );
      },
  'headless speech creates an unconfirmed note with explicit original provenance':
      () async {
        final vault = _ContentVault();
        final content = VaultContentService(vault: vault, ocr: _FailingOcr());
        await content.saveSpeechDraft(
          '  public transcript  ',
          blobId: 'original',
        );
        require(
          vault.store.savedDraft!.status == CardStatus.draft &&
              vault.store.savedDraft!.content == 'public transcript' &&
              vault.store.sourceKind == SourceKind.audio,
          'Speech confirmation/provenance changed',
        );
      },
  'domain review rules reject missing or non-bundle targets without a database':
      () async {
        final plan = ReviewedAgentPlan(
          reviewId: 'domain-check',
          sourceText: 'fixture',
          drafts: const [CardDraft(title: 'fixture', content: 'body')],
          providerLabel: 'fixture',
          actions: const [
            ReviewActions(bundleId: 'target', referenceIds: ['reference']),
          ],
        );
        Future<void> validate(Map<String, LifeCard?> targets) async =>
            plan.validateTargets(targets);
        await rejects(validate({}), '收纳组合已失效');
        await rejects(
          validate({'target': _card('target', CardKind.note)}),
          '收纳组合已失效',
        );
        await rejects(
          validate({'target': _card('target', CardKind.bundle)}),
          '引用卡片已失效',
        );
        plan.validateTargets({
          'target': _card('target', CardKind.bundle),
          'reference': _card('reference', CardKind.note),
        });
      },
};

Future<void> main() async {
  for (final entry in agentServiceChecks().entries) {
    await entry.value();
    // ignore: avoid_print -- standalone verification tool output.
    print('PASS ${entry.key}');
  }
}

LifeCard _card(String id, CardKind kind) => LifeCard(
  id: id,
  title: 'fixture',
  content: 'body',
  kind: kind,
  status: CardStatus.confirmed,
  tags: const [],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revisionNumber: 1,
);

class _Fixture {
  _Fixture(
    this.store,
    this.configuration,
    this.vault,
    this.provider,
    this.agent,
  );
  final HeadlessAiSettings store;
  final AgentSettingsService configuration;
  final _Vault vault;
  final HeadlessAiProvider provider;
  final AgentService agent;
  static Future<_Fixture> create() async {
    final store = HeadlessAiSettings();
    final configuration = AgentSettingsService(store);
    await configuration.initialize();
    final vault = _Vault();
    final provider = HeadlessAiProvider();
    return _Fixture(
      store,
      configuration,
      vault,
      provider,
      AgentService(
        vault: vault,
        configuration: configuration,
        provider: provider,
      ),
    );
  }

  void dispose() {
    agent.dispose();
    configuration.dispose();
  }
}

class HeadlessAiSettings implements AiSettingsRepository {
  AiProviderSettings selected = const AiProviderSettings(
    endpoint: 'https://fixture.invalid/chat',
    model: 'fixture-model',
    hasApiKey: true,
  );
  Future<String?>? pendingKey;
  Future<void>? pendingSave;
  bool rejectSave = false;
  @override
  Future<AiProviderSettings> read() async => selected;
  @override
  Future<List<AiProviderSettings>> readProfiles() async => [selected];
  @override
  Future<String?> readApiKey() async =>
      pendingKey == null ? 'fixture-key' : await pendingKey;
  @override
  Future<void> save({
    required String endpoint,
    required String model,
    String? apiKey,
  }) async {
    await pendingSave;
    selected = AiProviderSettings(
      endpoint: endpoint,
      model: model,
      hasApiKey: true,
    );
    if (rejectSave) throw StateError('fixture write failed');
  }

  @override
  Future<void> clear() async {
    selected = AgentSettingsService.empty;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected settings operation ${invocation.memberName}',
  );
}

class _Vault implements UnlockedVault {
  @override
  bool isUnlocked = true;
  @override
  int sessionGeneration = 1;
  final store = _Repository();
  @override
  VaultRepository get repository {
    if (!isUnlocked) throw StateError('locked fixture');
    return store;
  }
}

class HeadlessAiProvider implements AiProvider, AiConversationProvider {
  final requests = <AiProviderRequest>[];
  final replies = <Completer<AiConversationResponse>>[];
  Future<void> waitForRequests(int expected) async {
    for (var i = 0; i < 1000; i++) {
      if (requests.length >= expected) return;
      await Future<void>.delayed(Duration.zero);
    }
    throw StateError('Provider was never entered');
  }

  @override
  Future<AiConversationResponse> converse(
    AiProviderRequest request,
    List<Map<String, Object?>> history,
  ) {
    requests.add(request);
    final reply = Completer<AiConversationResponse>();
    replies.add(reply);
    return reply.future;
  }

  void complete(int index) => replies[index].complete(
    const AiConversationResponse(
      content: '{"reply":"fixture","cards":[]}',
      output: [],
    ),
  );
  @override
  Future<String> organize(AiProviderRequest request) =>
      throw UnsupportedError('Unexpected organize');
}

class _Repository implements VaultRepository {
  int reviewWrites = 0;
  List<CardDraft> reviewDrafts = const [];
  List<ReviewActions> reviewActions = const [];
  @override
  Future<List<LifeCard>> saveReviewedAgentSuggestions(
    String reviewId,
    String sourceText,
    List<CardDraft> drafts, {
    required String providerLabel,
    List<String> originalIds = const [],
    ReviewSource? reviewSource,
    List<ReviewActions> actions = const [],
  }) async {
    reviewWrites++;
    reviewDrafts = drafts;
    reviewActions = actions;
    return [];
  }

  @override
  Future<String?> readLocalValue(String key) async => jsonEncode({
    'version': 1,
    'actions': [for (final plan in reviewActions) plan.toJson()],
  });
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'Unexpected repository operation ${invocation.memberName}',
  );
}

class _SnapshotVault implements UnlockedVault {
  @override
  bool isUnlocked = true;
  @override
  int sessionGeneration = 1;
  final store = HeadlessSnapshotRepository();
  @override
  VaultRepository get repository => store;
}

class HeadlessSnapshotRepository extends _Repository {
  @override
  Future<List<CardReference>> cardReferences() async => [];
  Future<List<LifeCard>>? pendingCards;
  @override
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
    bool recycled = false,
  }) async => recycled
      ? []
      : await (pendingCards ??
            Future.value([_card('headless-card', CardKind.note)]));
  @override
  Future<List<VaultBlob>> listBlobs() async => [];
  @override
  Future<List<CredentialEntry>> listCredentials({
    String query = '',
    bool recycled = false,
  }) async => [];
  @override
  Future<List<ReleasePolicy>> listReleasePolicies() async => [];
  @override
  Future<List<LifeStateEvent>> lifeStateHistory() async => [];
  @override
  Future<LifeState> currentLifeState() async => LifeState.active;
  @override
  Future<VaultInsights> insights() async => const VaultInsights(
    totalCards: 1,
    drafts: 0,
    confirmed: 1,
    stale: 0,
    credentials: 0,
    byKind: {},
  );
  @override
  Future<List<String>> recycledOriginalIds() async => [];
  @override
  Future<DateTime?> lastBackupExport() async => null;
  @override
  Future<String?> readLocalValue(String key) async => null;
}

class _ContentVault implements VaultOriginals {
  @override
  bool isUnlocked = true;
  @override
  int sessionGeneration = 1;
  final store = _ContentRepository();
  @override
  VaultRepository get repository => store;
  bool deleted = false, readStarted = false;
  Uint8List clearBytes = Uint8List.fromList([1, 2, 3]);
  Future<Uint8List>? pendingRead;
  @override
  Future<VaultBlob> writeOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) async => store.blob;
  @override
  Future<Uint8List> readOriginal(VaultBlob blob) async {
    readStarted = true;
    return await (pendingRead ?? Future.value(clearBytes));
  }

  @override
  Future<void> deleteOriginal(VaultBlob blob) async {
    deleted = true;
  }
}

class _ContentRepository extends _Repository {
  final blob = VaultBlob(
    id: 'original',
    originalName: 'public.png',
    mediaKind: BlobMediaKind.image,
    mimeType: 'image/png',
    relativePath: 'original.blob',
    byteLength: 3,
    sha256: 'fixture-digest',
    createdAt: DateTime.utc(2026),
  );
  @override
  Future<VaultBlob?> getBlob(String id) async => id == blob.id ? blob : null;
  bool rejectRegistration = false;
  List<CredentialDraft> imported = [];
  CardDraft? savedDraft;
  SourceKind? sourceKind;
  @override
  Future<List<VaultBlob>> listBlobs() async => [blob];
  @override
  Future<LifeCard> registerBlob(VaultBlob blob) async {
    if (rejectRegistration) throw StateError('fixture register failed');
    return _card('original-card', CardKind.document);
  }

  @override
  Future<int> importCredentials(List<CredentialDraft> drafts) async {
    imported = drafts;
    return drafts.length;
  }

  @override
  Future<LifeCard> createCardFromOriginal(
    String blobId,
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String? sourceLabel,
  }) async {
    savedDraft = draft;
    this.sourceKind = sourceKind;
    return _card('speech-draft', CardKind.note);
  }
}

class _FailingOcr implements OcrProvider {
  @override
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  }) async => throw StateError('fixture OCR failed');
}
