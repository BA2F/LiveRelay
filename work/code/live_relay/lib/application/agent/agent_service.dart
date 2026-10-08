import 'dart:async';

import '../../core/ai/ai_privacy.dart';
import '../../core/ai/ai_provider_settings.dart';
import '../../core/ai/review_action_proposal.dart';
import '../../core/domain/entities.dart';
import '../../core/ports/ai_conversation_provider.dart';
import '../../core/ports/ai_provider.dart';
import '../../core/ports/vault_lifecycle.dart';
import '../draft_agent_service.dart';
import 'agent_settings_service.dart';

enum AgentActivity { idle, waiting }

/// Owns the network slot and authorization checks. No Flutter notifier, widget,
/// secure-storage plugin, database implementation or master key enters here.
class AgentService {
  AgentService({
    required this.vault,
    required this.configuration,
    required this.provider,
    this.drafts,
  });
  final VaultLifecycle vault;
  final AgentSettingsService configuration;
  final AiProvider provider;
  final DraftAgentService? drafts;
  final _activity = StreamController<AgentActivity>.broadcast();
  final _privacy = const AiPrivacyProcessor();
  AiCancellation? _cancellation;
  bool _disposed = false;
  bool get isBusy => _cancellation != null && !_cancellation!.isCancelled;
  Stream<AgentActivity> get activity => _activity.stream;
  Future<bool> commandAvailable() async =>
      await drafts?.commandAvailable() ?? false;

  void cancel() {
    final cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    cancellation.cancel();
    if (!_disposed) _activity.add(AgentActivity.idle);
  }

  AiTokenizedPayload prepare(String text, List<SensitiveMark> marks) =>
      (drafts ?? (throw StateError('Agent 尚未配置'))).prepare(text, marks);

  String previewOriginal(VaultBlob blob, List<SensitiveMark> marks) =>
      _privacy.tokenize(lines: blob.ocrLines, marks: marks).redactedText;

  Future<T> _request<T>(
    Future<T> Function(_AgentRequest) send, {
    bool requireResponses = false,
  }) async {
    if (_disposed) throw const FormatException('资料库已关闭');
    if (isBusy) throw const FormatException('请等待当前操作完成');
    if (configuration.isChanging) {
      throw const FormatException('服务配置正在保存，请等待保存完成后重新检查本轮发送范围');
    }
    if (!vault.isUnlocked) throw StateError('请先解锁资料库');
    if (vault.isMaintaining) throw StateError('资料库维护正在进行');
    final settings = configuration.settings;
    if (!settings.isConfigured) {
      throw const FormatException('请先配置 AI 服务；也可以在我的资料中手动新建卡片');
    }
    if (requireResponses && settings.protocol != AiProtocol.responses) {
      throw StateError('请在 AI 服务设置中选择 Responses 并配置服务');
    }
    final generation = configuration.generation;
    final sessionGeneration = vault.sessionGeneration;
    final cancellation = AiCancellation();
    _cancellation = cancellation;
    _activity.add(AgentActivity.waiting);
    try {
      final key = await configuration.readApiKey();
      cancellation.check();
      if (_disposed ||
          !vault.isUnlocked ||
          sessionGeneration != vault.sessionGeneration ||
          key == null ||
          key.isEmpty) {
        throw const FormatException('服务密钥不存在或资料库已锁定');
      }
      _checkConfiguration(settings, generation, afterSend: false);
      void ensureCurrent() {
        cancellation.check();
        if (_disposed ||
            !vault.isUnlocked ||
            sessionGeneration != vault.sessionGeneration) {
          throw const FormatException('资料库已锁定，本次结果已丢弃');
        }
        _checkConfiguration(settings, generation, afterSend: true);
      }

      final result = await send(
        _AgentRequest(settings, key, cancellation, ensureCurrent),
      );
      ensureCurrent();
      return result;
    } finally {
      if (identical(_cancellation, cancellation)) _cancellation = null;
      if (!_disposed) {
        _activity.add(isBusy ? AgentActivity.waiting : AgentActivity.idle);
      }
    }
  }

  void _checkConfiguration(
    AiProviderSettings settings,
    int generation, {
    required bool afterSend,
  }) {
    if (generation != configuration.generation ||
        !identical(settings, configuration.settings)) {
      throw FormatException(
        afterSend ? '服务配置已变化，本次结果已丢弃' : '服务配置已变化，请重新检查本轮发送范围',
      );
    }
  }

  Future<AiConversationResponse> converse(
    String text,
    List<Map<String, Object?>> history, {
    List<Map<String, Object?>>? inputContent,
    List<ReviewTarget> reviewTargets = const [],
  }) => _request((request) {
    final settings = request.settings;
    final selected = provider;
    if (selected is! AiConversationProvider) {
      throw const FormatException('此 AI 服务尚未支持持续对话');
    }
    return (selected as AiConversationProvider).converse(
      AiProviderRequest(
        endpoint: Uri.parse(settings.endpoint),
        model: settings.model,
        apiKey: request.key,
        protocol: settings.protocol,
        redactedText: text,
        inputContent: inputContent,
        reviewTargets: reviewTargets,
        cancellation: request.cancellation,
      ),
      history,
    );
  });

  Future<AgentDraftBatch> propose(
    String text,
    List<SensitiveMark> marks, {
    bool allowCommands = false,
  }) => _request(
    (request) => (drafts ?? (throw StateError('Agent 尚未配置'))).propose(
      text: text,
      marks: marks,
      endpoint: Uri.parse(request.settings.endpoint),
      model: request.settings.model,
      apiKey: request.key,
      cancellation: request.cancellation,
      allowCommands: allowCommands,
    ),
    requireResponses: true,
  );

  Future<int> organizeOriginal(VaultBlob blob, List<SensitiveMark> marks) {
    final input = List<SensitiveMark>.unmodifiable(marks);
    final payload = _privacy.tokenize(lines: blob.ocrLines, marks: input);
    return _request((request) async {
      await vault.runMutation(() async {
        request.ensureCurrent();
        await vault.repository.saveSensitiveMarks(blob.id, input);
        request.ensureCurrent();
      });
      request.ensureCurrent();
      final settings = request.settings;
      final response = await provider.organize(
        AiProviderRequest(
          endpoint: Uri.parse(settings.endpoint),
          apiKey: request.key,
          model: settings.model,
          redactedText: payload.redactedText,
          protocol: settings.protocol,
          cancellation: request.cancellation,
        ),
      );
      request.ensureCurrent();
      final suggestions = _privacy.validateAndRehydrate(response, payload);
      final cards = await vault.runMutation(() async {
        request.ensureCurrent();
        final saved = await vault.repository.saveAiSuggestions(
          blob.id,
          suggestions.map((s) => s.toDraft()).toList(growable: false),
          providerLabel:
              '获授权云 AI · ${settings.model} · ${Uri.parse(settings.endpoint).host}',
        );
        request.ensureCurrent();
        return saved;
      });
      return cards.length;
    });
  }

  void dispose() {
    cancel();
    _disposed = true;
    unawaited(_activity.close());
  }
}

class _AgentRequest {
  const _AgentRequest(
    this.settings,
    this.key,
    this.cancellation,
    this.ensureCurrent,
  );
  final AiProviderSettings settings;
  final String key;
  final AiCancellation cancellation;
  final void Function() ensureCurrent;
}
