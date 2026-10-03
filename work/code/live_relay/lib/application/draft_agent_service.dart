import '../core/ai/ai_privacy.dart';
import '../core/domain/entities.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/agent_command_provider.dart';

class AgentDraftBatch {
  const AgentDraftBatch({
    required this.sourceText,
    required this.providerLabel,
    required this.suggestions,
    this.commandHistory = const [],
  });
  final String sourceText;
  final String providerLabel;
  final List<AiCardSuggestion> suggestions;
  final List<AgentCommandResult> commandHistory;
}

class DraftAgentService {
  const DraftAgentService(this.provider, {this.commands});
  final AiProvider provider;
  final AgentCommandProvider? commands;
  Future<bool> commandAvailable() async => await commands?.available() ?? false;
  static const privacy = AiPrivacyProcessor();

  AiTokenizedPayload prepare(String text, List<SensitiveMark> marks) {
    if (text.trim().isEmpty || text.length > 32000) {
      throw const FormatException('请填写资料，单次最多 32000 个字符');
    }
    final lines = text.split('\n');
    if (lines.length > 200) throw const FormatException('单次最多 200 行，请分批整理');
    if (marks.any((m) => m.lineOrder < 0 || m.lineOrder >= lines.length)) {
      throw const FormatException('敏感标记位置错误');
    }
    return privacy.tokenize(
      lines: [
        for (var i = 0; i < lines.length; i++)
          OcrLine(
            text: lines[i],
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
            order: i,
          ),
      ],
      marks: marks,
    );
  }

  Future<AgentDraftBatch> propose({
    required String text,
    required List<SensitiveMark> marks,
    required Uri endpoint,
    required String model,
    required String apiKey,
    AiCancellation? cancellation,
    bool allowCommands = false,
  }) async {
    final payload = prepare(text, marks);
    AgentCommandSession? session;
    try {
      if (allowCommands) {
        if (commands == null) throw const FormatException('此设备尚未提供隔离命令');
        session = await commands!.open(
          payload.redactedText,
          whenCancelled: cancellation?.whenCancelled,
        );
      }
      final result = await provider.organize(
        AiProviderRequest(
          endpoint: endpoint,
          apiKey: apiKey,
          model: model,
          redactedText: payload.redactedText,
          protocol: AiProtocol.responses,
          cancellation: cancellation,
          commandSession: session,
        ),
      );
      cancellation?.check();
      return AgentDraftBatch(
        commandHistory: session?.history ?? const [],
        sourceText: text,
        providerLabel: '获授权 Agent · $model · ${endpoint.host}',
        suggestions: List.unmodifiable(
          privacy.validateAndRehydrate(result, payload),
        ),
      );
    } finally {
      await session?.close();
    }
  }
}
