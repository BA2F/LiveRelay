// Records commands through a real session gate, no Flutter/SQLite/platform IO.
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/application/local_handoff_service.dart';
import 'package:live_relay/core/ports/ai_provider.dart';
import 'package:live_relay/core/identity/local_identity.dart';
import 'package:live_relay/application/vault_records_application.dart';
import 'package:live_relay/application/vault_snapshot_query.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/application/agent/agent_settings_service.dart';
import 'package:live_relay/application/agent/agent_service.dart';
import 'package:live_relay/core/domain/entities.dart';

import 'agent_service_headless_checks.dart'
    show HeadlessSnapshotRepository, HeadlessAiSettings, HeadlessAiProvider;
import 'conversation_headless_checks.dart' show Biometrics, Blobs, Ocr;
import 'maintenance_headless_checks.dart' show FakeInstallation;

void check(bool v, String reason) {
  if (!v) throw StateError(reason);
}

Future<void> reject(Future<Object?> value, String message) async {
  Object? failure;
  try {
    await value;
  } on Object catch (e) {
    failure = e;
  }
  check(
    failure != null && '$failure'.contains(message),
    'Expected $message; got $failure',
  );
}

LifeCard card(CardDraft draft, {int number = 1}) => LifeCard(
  id: 'public-card',
  title: draft.title,
  content: draft.content,
  kind: draft.kind,
  status: draft.status,
  tags: draft.tags,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revisionNumber: number,
);

class Repository extends HeadlessSnapshotRepository {
  final cards = <LifeCard>[];
  final local = <String, String>{};
  List<SensitiveMark> marks = [];
  Completer<void>? pendingAiSave;
  final aiEntered = Completer<void>();
  int aiSaves = 0;
  @override
  Future<String?> readLocalValue(String key) async => local[key];
  @override
  Future<void> writeLocalValue(String key, String value) async {
    if (!entered.isCompleted) entered.complete();
    await pendingWrite?.future;
    local[key] = value;
  }

  @override
  Future<void> saveSensitiveMarks(String id, List<SensitiveMark> value) async {
    marks = List.of(value);
  }

  @override
  Future<List<LifeCard>> saveAiSuggestions(
    String id,
    List<CardDraft> drafts, {
    required String providerLabel,
  }) async {
    aiSaves++;
    if (!aiEntered.isCompleted) aiEntered.complete();
    await pendingAiSave?.future;
    final saved = drafts.map((d) => card(d)).toList();
    cards.addAll(saved);
    return saved;
  }

  List<CredentialDraft> imports = [];
  Completer<void>? pendingWrite;
  Completer<LifeCard?>? pendingRead;
  final entered = Completer<void>();
  bool failWrite = false;
  int writes = 0;
  @override
  Future<List<LifeCard>> listCards({
    String query = '',
    CardKind? kind,
    CardStatus? status,
    bool recycled = false,
  }) async =>
      recycled ? [] : await (pendingCards ?? Future.value(List.of(cards)));
  @override
  Future<LifeCard> createCard(
    CardDraft draft, {
    SourceKind sourceKind = SourceKind.ownerInput,
    String sourceLabel = '本人输入',
  }) async {
    writes++;
    if (!entered.isCompleted) entered.complete();
    await pendingWrite?.future;
    if (failWrite) throw StateError('write denied');
    final next = card(draft);
    cards.add(next);
    return next;
  }

  @override
  Future<LifeCard?> getCard(String id) async =>
      pendingRead != null ? pendingRead!.future : cards.firstOrNull;
  @override
  Future<int> importCredentials(List<CredentialDraft> drafts) async {
    imports = drafts;
    return drafts.length;
  }

  @override
  Future<void> close() async {}
}

class OrganizingProvider extends HeadlessAiProvider {
  final entered = Completer<void>();
  final reply = Completer<String>();
  @override
  Future<String> organize(AiProviderRequest request) {
    requests.add(request);
    entered.complete();
    return reply.future;
  }

  void completeOrganize() => reply.complete(
    jsonEncode({
      'cards': [
        {
          'title': 'Public organized',
          'content': requests.single.redactedText,
          'kind': 'note',
          'inference': false,
        },
      ],
    }),
  );
}

VaultBlob publicOcr() => VaultBlob(
  id: 'public-original',
  originalName: 'Public.png',
  mediaKind: BlobMediaKind.image,
  mimeType: 'image/png',
  relativePath: 'public.blob',
  byteLength: 3,
  sha256: 'public',
  createdAt: DateTime.utc(2026),
  ocrLines: const [
    OcrLine(
      text: 'public-sensitive-fixture',
      left: 0,
      top: 0,
      right: 1,
      bottom: 1,
      order: 0,
    ),
  ],
);

class Fixture {
  Fixture(this.session, this.repository, this.snapshots, this.application);
  final VaultSession session;
  final Repository repository;
  final VaultSnapshotQuery snapshots;
  final VaultRecordsApplication application;
  static Future<Fixture> make() async {
    final repository = Repository();
    final session = VaultSession(
      resolveDirectory: () async => Directory('/unused-public-fixture'),
      loadPassphraseCodec: () async => throw UnsupportedError('not used'),
      openRepository: (_, _) async => repository,
      biometricKeyStore: Biometrics(),
      blobStore: Blobs(),
      installationFactory: (_) => FakeInstallation(),
    );
    await session.prepare();
    final key = Uint8List(32);
    try {
      await session.openWithKey(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
    session.markUnlocked();
    final snapshots = VaultSnapshotQuery(session);
    await snapshots.load();
    return Fixture(
      session,
      repository,
      snapshots,
      VaultRecordsApplication(
        vault: session,
        content: VaultContentService(vault: session, ocr: Ocr()),
        snapshots: snapshots,
      ),
    );
  }

  void dispose() {
    snapshots.dispose();
    session.dispose();
  }
}

Map<String, Future<void> Function()> recordsChecks() => {
  'headless typed record command freezes input and publishes fresh snapshot':
      () async {
        final f = await Fixture.make();
        final events = <VaultSnapshot>[];
        final subscription = f.snapshots.changes.listen(events.add);
        try {
          final tags = ['public'],
              draft = CardDraft(
                title: 'Public title',
                content: 'Public body',
                tags: ['public'],
              );
          f.repository.pendingWrite = Completer<void>();
          final result = f.application.createCard(
            CardDraft(title: draft.title, content: draft.content, tags: tags),
          );
          await f.repository.entered.future;
          tags.clear();
          f.repository.pendingWrite!.complete();
          final saved = await result;
          check(
            saved.tags.single == 'public' &&
                f.snapshots.current!.cards.single.title == 'Public title' &&
                (await f.application.getCard(saved.id))!.content ==
                    'Public body',
            'Use case lost input or snapshot',
          );
          await Future<void>.delayed(Duration.zero);
          check(
            events.length == 1 && !f.session.isWriting,
            'Snapshot event missing or command gate leaked',
          );
        } finally {
          await subscription.cancel();
          f.dispose();
        }
      },
  'headless record command excludes maintenance and lock discards late result':
      () async {
        final f = await Fixture.make();
        try {
          f.repository.pendingWrite = Completer<void>();
          final rejected = reject(
            f.application.createCard(
              const CardDraft(title: 'Public title', content: 'Public body'),
            ),
            '已关闭或重开',
          );
          await f.repository.entered.future;
          await reject(
            f.session.exclusiveMaintenance<void>(() async {}),
            '维护正在进行',
          );
          await reject(
            f.application.createCard(
              const CardDraft(title: 'Other', content: 'Public body'),
            ),
            '等待当前资料库操作',
          );
          await f.session.close();
          f.repository.pendingWrite!.complete();
          await rejected;
          check(
            f.snapshots.current == null &&
                !f.session.isWriting &&
                f.repository.writes == 1,
            'Late write revived view',
          );
        } finally {
          f.dispose();
        }
      },
  'headless consumed file inputs wipe even when command gate rejects before service':
      () async {
        final f = await Fixture.make();
        try {
          final entered = Completer<void>(), release = Completer<void>();
          final holding = f.session.runMutation(() async {
            entered.complete();
            await release.future;
          });
          await entered.future;
          final original = Uint8List.fromList([1, 2, 3]),
              csv = Uint8List.fromList([4, 5, 6]);
          await reject(
            f.application.importOriginal(
              bytes: original,
              originalName: 'Public.png',
              mimeType: 'image/png',
              mediaKind: BlobMediaKind.image,
            ),
            '等待当前资料库操作',
          );
          await reject(f.application.importEdgePasswords(csv), '等待当前资料库操作');
          check(
            original.every((b) => b == 0) &&
                csv.every((b) => b == 0) &&
                f.repository.imports.isEmpty,
            'Rejected bytes leaked or were parsed',
          );
          release.complete();
          await holding;
        } finally {
          f.dispose();
        }
      },
  'headless record query cannot return a private result after lock': () async {
    final f = await Fixture.make();
    try {
      f.repository.pendingRead = Completer<LifeCard?>();
      final rejected = reject(f.application.getCard('public-card'), '已关闭或重开');
      await Future<void>.delayed(Duration.zero);
      await f.session.close();
      f.repository.pendingRead!.complete(
        card(const CardDraft(title: 'Public title', content: 'Public body')),
      );
      await rejected;
      check(f.snapshots.current == null, 'Revoked query cached data');
    } finally {
      f.dispose();
    }
  },
  'headless records save during Agent wait and CSV keeps exact secret':
      () async {
        final f = await Fixture.make();
        final configuration = AgentSettingsService(HeadlessAiSettings());
        await configuration.initialize();
        final provider = HeadlessAiProvider();
        final agent = AgentService(
          vault: f.session,
          configuration: configuration,
          provider: provider,
        );
        try {
          final reply = agent.converse('public fixture', []);
          await provider.waitForRequests(1);
          await f.application.createCard(
            const CardDraft(
              title: 'Public while waiting',
              content: 'Public body',
            ),
          );
          check(
            agent.isBusy &&
                !f.session.isWriting &&
                f.snapshots.current!.cards.length == 1,
            'Network wait blocked records',
          );
          final bytes = Uint8List.fromList(
            'name,url,username,password\nPublic,https://fixture.invalid,user,  exact  \n'
                .codeUnits,
          );
          final imported = await f.application.importEdgePasswords(bytes);
          check(
            imported.entries.length == 1 &&
                f.repository.imports.single.secret == '  exact  ' &&
                bytes.every((b) => b == 0),
            'Import altered secret or retained CSV',
          );
          provider.complete(0);
          await reply;
        } finally {
          agent.dispose();
          configuration.dispose();
          f.dispose();
        }
      },
  'headless failed record command keeps last snapshot and releases write gate':
      () async {
        final f = await Fixture.make();
        try {
          final before = f.snapshots.current;
          f.repository.failWrite = true;
          await reject(
            f.application.createCard(
              const CardDraft(title: 'Public title', content: 'Public body'),
            ),
            'write denied',
          );
          check(
            identical(before, f.snapshots.current) && !f.session.isWriting,
            'Failed command changed snapshot or stuck gate',
          );
          f.repository.failWrite = false;
          await f.application.createCard(
            const CardDraft(title: 'Retry', content: 'Public body'),
          );
          check(
            f.snapshots.current!.cards.single.title == 'Retry',
            'Failed command could not retry',
          );
        } finally {
          f.dispose();
        }
      },
};
Map<String, Future<void> Function()> snapshotPublicationChecks() => {
  'typed snapshot publication completes presentation mapping before command resolves':
      () async {
        final f = await Fixture.make();
        String? observed;
        final subscription = f.snapshots.changes.listen(
          (snapshot) => observed = snapshot.cards.single.title,
        );
        try {
          await f.application.createCard(
            const CardDraft(
              title: 'Public synchronous title',
              content: 'Public body',
            ),
          );
          check(
            observed == 'Public synchronous title',
            'Projection still stale when save completed',
          );
        } finally {
          await subscription.cancel();
          f.dispose();
        }
      },
  'snapshot publication observer lock revokes cache and rejects the returning query':
      () async {
        final f = await Fixture.make();
        Future<void>? closing;
        final subscription = f.snapshots.changes.listen((_) {
          closing = f.session.close();
        });
        try {
          await reject(f.snapshots.load(), '已关闭或重开');
          await closing;
          check(
            f.snapshots.current == null && !f.session.isUnlocked,
            'Observer lock retained published cache',
          );
        } finally {
          await subscription.cancel();
          f.dispose();
        }
      },
  'older snapshot query cannot replace a newer published projection': () async {
    final f = await Fixture.make();
    final older = Completer<List<LifeCard>>();
    try {
      f.repository.pendingCards = older.future;
      final rejected = reject(f.snapshots.load(), '较新的查询');
      await Future<void>.delayed(Duration.zero);
      f.repository.pendingCards = null;
      f.repository.cards.add(
        card(
          const CardDraft(title: 'Newer public title', content: 'Public body'),
        ),
      );
      await f.snapshots.load();
      older.complete([
        card(
          const CardDraft(title: 'Older public title', content: 'Public body'),
        ),
      ]);
      await rejected;
      check(
        f.snapshots.current!.cards.single.title == 'Newer public title',
        'Old result overwrote fresh snapshot',
      );
    } finally {
      f.dispose();
    }
  },
};

Map<String, Future<void> Function()> ownerAgentChecks() => {
  'headless owner profile command shares the gate and lock discards completion':
      () async {
        final f = await Fixture.make();
        final owner = LocalHandoffService(f.session, originals: f.session);
        try {
          f.repository.pendingWrite = Completer<void>();
          final rejected = reject(
            owner.saveProfile('Public owner', 'public', 'public'),
            '已锁定',
          );
          await f.repository.entered.future;
          await reject(
            f.application.createCard(
              const CardDraft(title: 'Public title', content: 'Public body'),
            ),
            '等待',
          );
          await reject(f.session.exclusiveMaintenance<void>(() async {}), '维护');
          await f.session.close();
          f.repository.pendingWrite!.complete();
          await rejected;
          check(
            !f.session.isWriting && f.snapshots.current == null,
            'Owner write revived session',
          );
          await reject(owner.profile(), '请先解锁');
        } finally {
          f.dispose();
        }
      },
  'headless first owner identity initializes exactly once under the shared gate':
      () async {
        final f = await Fixture.make();
        final owner = LocalHandoffService(f.session, originals: f.session);
        try {
          f.repository.pendingWrite = Completer<void>();
          final first = owner.publicIdentity();
          await f.repository.entered.future;
          await reject(owner.publicIdentity(), '等待');
          f.repository.pendingWrite!.complete();
          final public = await first;
          final again = await owner.publicIdentity();
          check(
            await LocalIdentity.fingerprintOf(public) ==
                    await LocalIdentity.fingerprintOf(again) &&
                f.repository.local.containsKey('handoff.owner') &&
                !f.session.isWriting,
            'Owner initialized twice or gate leaked',
          );
        } finally {
          f.dispose();
        }
      },
  'headless original Agent freezes marks before credential wait and permits local save during network':
      () async {
        final f = await Fixture.make(), store = HeadlessAiSettings();
        final key = Completer<String?>();
        store.pendingKey = key.future;
        final configuration = AgentSettingsService(store);
        await configuration.initialize();
        final provider = OrganizingProvider();
        final service = AgentService(
          vault: f.session,
          configuration: configuration,
          provider: provider,
        );
        try {
          final marks = [
            const SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.note),
          ];
          final result = service.organizeOriginal(publicOcr(), marks);
          marks.clear();
          key.complete('public-fixture-key');
          await provider.entered.future;
          check(
            provider.requests.single.redactedText == '[[NOTE_01]]' &&
                f.repository.marks.length == 1 &&
                !f.session.isWriting &&
                service.isBusy,
            'Disclosure changed or network held local gate',
          );
          await f.application.createCard(
            const CardDraft(
              title: 'Public during wait',
              content: 'Public body',
            ),
          );
          provider.completeOrganize();
          check(
            await result == 1 && f.repository.aiSaves == 1,
            'Agent draft not persisted',
          );
        } finally {
          service.dispose();
          configuration.dispose();
          f.dispose();
        }
      },
  'headless Agent persistence excludes maintenance and lock discards late saved result':
      () async {
        final f = await Fixture.make();
        final configuration = AgentSettingsService(HeadlessAiSettings());
        await configuration.initialize();
        final provider = OrganizingProvider();
        final agent = AgentService(
          vault: f.session,
          configuration: configuration,
          provider: provider,
        );
        try {
          f.repository.pendingAiSave = Completer<void>();
          final rejected = reject(
            agent.organizeOriginal(publicOcr(), []),
            '已锁定',
          );
          await provider.entered.future;
          provider.completeOrganize();
          await f.repository.aiEntered.future;
          await reject(f.session.exclusiveMaintenance<void>(() async {}), '维护');
          await f.session.close();
          f.repository.pendingAiSave!.complete();
          await rejected;
          check(
            f.snapshots.current == null &&
                !f.session.isWriting &&
                !agent.isBusy,
            'Agent late save revived session',
          );
        } finally {
          agent.dispose();
          configuration.dispose();
          f.dispose();
        }
      },
};

Future<void> main() async {
  for (final entry in {
    ...recordsChecks(),
    ...ownerAgentChecks(),
    ...snapshotPublicationChecks(),
  }.entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
