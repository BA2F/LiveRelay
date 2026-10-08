// End-to-end application conversation runs in ordinary Dart with a real session
// lifecycle and in-memory repository/provider adapters; no Flutter controller.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:live_relay/application/agent/agent_review_service.dart';
import 'package:live_relay/application/agent/agent_service.dart';
import 'package:live_relay/application/agent/agent_settings_service.dart';
import 'package:live_relay/application/agent/conversation_application.dart';
import 'package:live_relay/application/agent/conversation_runtime.dart';
import 'package:live_relay/application/vault_content_service.dart';
import 'package:live_relay/application/draft_agent_service.dart';
import 'package:live_relay/application/vault_session.dart';
import 'package:live_relay/application/vault_snapshot_query.dart';
import 'package:live_relay/core/ai/conversation_state.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/ports/biometric_key_store.dart';
import 'package:live_relay/core/ports/vault_blob_store.dart';
import 'package:live_relay/core/ports/ocr_provider.dart';

import 'agent_service_headless_checks.dart'
    show HeadlessAiSettings, HeadlessAiProvider, HeadlessSnapshotRepository;
import 'maintenance_headless_checks.dart' show FakeInstallation;

void check(bool v, String message) {
  if (!v) throw StateError(message);
}

Future<void> reject(Future<Object?> f, String message) async {
  Object? error;
  try {
    await f;
  } on Object catch (e) {
    error = e;
  }
  check(
    error != null && '$error'.contains(message),
    'Expected $message; got $error',
  );
}

Map<String, Future<void> Function()> conversationChecks() => {
  'headless conversation sends, persists and reopens without presentation dependencies':
      () async {
        final f = await Fixture.make();
        ConversationRuntime? reopened;
        try {
          f.runtime.updateDraft('public fixture turn');
          final pending = f.runtime.send(
            f.runtime.prepare(f.runtime.draft, []),
          );
          await f.provider.waitForRequests(1);
          check(
            f.session.isWriting == false && f.agent.isBusy,
            'Network occupied local command gate',
          );
          f.provider.complete(0);
          check(
            await pending &&
                f.runtime.messages.length == 2 &&
                f.runtime.draft.isEmpty,
            'Turn not applied',
          );
          check(
            f.repository.saved != null &&
                jsonDecode(f.repository.saved!)['version'] == 1,
            'Persistence format changed',
          );
          reopened = ConversationRuntime(f.application);
          await reopened.load();
          check(
            reopened.messages.length == 2 &&
                reopened.messages.last.text == 'fixture',
            'Round trip failed',
          );
        } finally {
          reopened?.dispose();
          f.dispose();
        }
      },
  'real session lock synchronously clears conversation plaintext and late network reply':
      () async {
        final f = await Fixture.make();
        try {
          f.runtime.updateDraft('public fixture input');
          final pending = f.runtime.send(
            f.runtime.prepare(f.runtime.draft, []),
          );
          await f.provider.waitForRequests(1);
          final closing = f.session.close();
          check(
            f.runtime.messages.isEmpty &&
                f.runtime.draft.isEmpty &&
                !f.runtime.working &&
                f.snapshots.current == null,
            'Revocation was delayed',
          );
          await closing;
          f.provider.complete(0);
          check(
            !await pending && f.runtime.messages.isEmpty && !f.agent.isBusy,
            'Late result was retained',
          );
        } finally {
          f.dispose();
        }
      },
  'headless review uses one atomic application command and publishes complete query state':
      () async {
        final f = await Fixture.make();
        try {
          final message = ConversationMessage(
            'assistant',
            'public review',
            suggestions: const [
              AiCardSuggestion(
                title: 'fixture card',
                content: 'fixture body',
                kind: CardKind.note,
                isInference: false,
              ),
            ],
          );
          f.runtime.messages.addAll([
            ConversationMessage('user', 'public input'),
            message,
          ]);
          await f.runtime.accept(message);
          check(
            message.accepted &&
                f.repository.reviewWrites == 1 &&
                f.repository.reviewDrafts.single.status == CardStatus.confirmed,
            'Review not applied through one command',
          );
          check(
            f.snapshots.current != null && !f.session.isWriting,
            'Projection/command slot not released',
          );
          final data = jsonDecode(f.repository.saved!) as Map;
          check(
            (data['messages'] as List).last['accepted'] == true,
            'Accepted state not persisted',
          );
        } finally {
          f.dispose();
        }
      },
  'headless read failure blocks overwrite until explicit new conversation':
      () async {
        final f = await Fixture.make();
        try {
          f.repository.saved = '{"version":9}';
          await reject(f.runtime.load(), '版本不支持');
          await reject(f.runtime.flush(), '明确开始新会话');
          check(
            f.repository.saved == '{"version":9}',
            'Unreadable state overwritten',
          );
          await f.runtime.newConversation();
          check(
            jsonDecode(f.repository.saved!)['version'] == 1,
            'Explicit recovery did not save',
          );
        } finally {
          f.dispose();
        }
      },
  'headless pending conversation save excludes maintenance and rejects lock-then-complete':
      () async {
        final f = await Fixture.make();
        try {
          f.repository.pendingSave = Completer<void>();
          f.runtime.updateDraft('public pending draft');
          final rejected = reject(f.runtime.flush(), '已关闭');
          await f.repository.writeEntered.future;
          await reject(f.session.exclusiveMaintenance(() async => 1), '维护正在进行');
          check(f.session.isWriting, 'Command gate missing');
          final consumed = Uint8List.fromList([1, 2, 3]);
          await reject(
            f.application.importOriginal(
              bytes: consumed,
              originalName: 'public.txt',
              mimeType: 'text/plain',
              mediaKind: BlobMediaKind.document,
            ),
            '等待',
          );
          check(
            consumed.every((b) => b == 0),
            'Busy rejection retained consumed original bytes',
          );
          await f.session.close();
          f.repository.pendingSave!.complete();
          await rejected;
          check(
            !f.session.isWriting && f.runtime.draft.isEmpty,
            'Late save restored memory/gate',
          );
        } finally {
          f.dispose();
        }
      },
};

class Fixture {
  Fixture(
    this.session,
    this.repository,
    this.provider,
    this.settings,
    this.agent,
    this.snapshots,
    this.application,
    this.runtime,
  );
  final VaultSession session;
  final Repository repository;
  final HeadlessAiProvider provider;
  final AgentSettingsService settings;
  final AgentService agent;
  final VaultSnapshotQuery snapshots;
  final ConversationApplication application;
  final ConversationRuntime runtime;
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
    final key = Uint8List.fromList(List.filled(32, 7));
    try {
      await session.openWithKey(key);
    } finally {
      key.fillRange(0, key.length, 0);
    }
    session.markUnlocked();
    final settings = AgentSettingsService(HeadlessAiSettings());
    await settings.initialize();
    final provider = HeadlessAiProvider();
    final agent = AgentService(
      vault: session,
      configuration: settings,
      provider: provider,
      drafts: DraftAgentService(provider),
    );
    final snapshots = VaultSnapshotQuery(session);
    await snapshots.load();
    final application = ConversationApplication(
      vault: session,
      settings: settings,
      agent: agent,
      review: AgentReviewService(session),
      content: VaultContentService(vault: session, ocr: Ocr()),
      snapshots: snapshots,
    );
    return Fixture(
      session,
      repository,
      provider,
      settings,
      agent,
      snapshots,
      application,
      ConversationRuntime(application),
    );
  }

  void dispose() {
    runtime.dispose();
    agent.dispose();
    settings.dispose();
    snapshots.dispose();
    session.dispose();
  }
}

class Repository extends HeadlessSnapshotRepository {
  String? saved;
  Completer<void>? pendingSave;
  final writeEntered = Completer<void>();
  @override
  Future<String?> readChunkedLocalValue(String name) async => saved;
  @override
  Future<void> writeChunkedLocalValue(String name, String value) async {
    if (!writeEntered.isCompleted) writeEntered.complete();
    if (pendingSave != null) await pendingSave!.future;
    saved = value;
  }

  @override
  Future<String?> readLocalValue(String key) async =>
      key.startsWith('agent.plan.')
      ? jsonEncode({
          'version': 1,
          'actions': [for (final a in reviewActions) a.toJson()],
        })
      : null;
  @override
  Future<void> close() async {}
}

class Biometrics implements BiometricKeyStore {
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<void> clear() async {}
  @override
  Future<Uint8List?> readMasterKey() async => null;
  @override
  Future<void> saveMasterKey(Uint8List masterKey) async =>
      throw UnsupportedError('not used');
}

class Blobs implements VaultBlobStore {
  @override
  dynamic noSuchMethod(Invocation i) =>
      throw UnsupportedError('Unused blob operation ${i.memberName}');
}

class Ocr implements OcrProvider {
  @override
  Future<OcrResult> recognize({
    required Uint8List imageBytes,
    required String originalName,
  }) => throw UnsupportedError('not used');
}

Future<void> main() async {
  for (final entry in conversationChecks().entries) {
    await entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
