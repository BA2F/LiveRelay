import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../app_controller.dart';
import '../../core/ai/ai_privacy.dart';
import '../../core/domain/entities.dart';

class PreparedConversationTurn {
  const PreparedConversationTurn(
    this.text,
    this.payload,
    this.generation,
    this.turn,
    this.provider,
  );
  final int generation, turn;
  final String provider;
  final String text;
  final AiTokenizedPayload payload;
}

class ConversationMessage {
  ConversationMessage(
    this.role,
    this.text, {
    List<AiCardSuggestion> suggestions = const [],
    String? reviewId,
    this.providerLabel = '',
    this.accepted = false,
  }) : suggestions = List.of(suggestions),
       reviewId = reviewId ?? const Uuid().v7();
  final String role, text, reviewId, providerLabel;
  final List<AiCardSuggestion> suggestions;
  bool accepted;
}

/// One encrypted conversation per vault; view lifetimes do not own its contents.
class AgentConversation extends ChangeNotifier {
  AgentConversation(this.controller) {
    controller.addListener(_sessionChanged);
  }
  void _sessionChanged() {
    if (!controller.isUnlocked) {
      clear();
      if (!_disposed) notifyListeners();
    }
  }

  String get _configuration {
    final s = controller.aiSettings;
    return '${s.protocol.name}:${s.endpoint}:${s.model}';
  }

  final AppController controller;
  final messages = <ConversationMessage>[];
  final _history = <Map<String, Object?>>[];
  final _tokens = <String, String>{};
  final marks = <int, SensitiveFieldKind>{};
  String draft = '';
  bool working = false, _disposed = false, _persistenceBlocked = false;
  String? error, _providerFingerprint;
  int _turn = 0, _generation = 0;
  Timer? _saveTimer;
  Future<void> _writes = Future.value();
  static final _pattern = RegExp(r'\[\[[A-Z][A-Z0-9_]*_\d{2}\]\]');

  PreparedConversationTurn prepare(String text, List<SensitiveMark> marks) {
    final payload = controller.prepareConversationText(text, marks);
    var redacted = payload.redactedText;
    final tokens = <String, String>{};
    for (final entry in payload.tokenMap.entries) {
      final token = '[[TURN${_turn + 1}_${entry.key.substring(2)}';
      redacted = redacted.replaceAll(entry.key, token);
      tokens[token] = entry.value;
    }
    return PreparedConversationTurn(
      text,
      AiTokenizedPayload(redactedText: redacted, tokenMap: tokens),
      _generation,
      _turn,
      _configuration,
    );
  }

  String get disclosureHistory => _history.map(jsonEncode).join('\n');
  void updateDraft(String text) {
    draft = text;
    marks.removeWhere((line, _) => line >= text.split('\n').length);
    _scheduleSave();
    notifyListeners();
  }

  void mark(int line, SensitiveFieldKind? kind) {
    if (kind == null) {
      marks.remove(line);
    } else {
      marks[line] = kind;
    }
    _scheduleSave();
    notifyListeners();
  }

  void editSuggestion(
    ConversationMessage message,
    int index, {
    String? title,
    String? content,
  }) {
    if (message.accepted || working) return;
    final s = message.suggestions[index];
    message.suggestions[index] = AiCardSuggestion(
      title: title ?? s.title,
      content: content ?? s.content,
      kind: s.kind,
      isInference: s.isInference,
    );
    _scheduleSave();
    notifyListeners();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
      const Duration(milliseconds: 650),
      () => unawaited(retrySave()),
    );
  }

  Future<void> load() async {
    try {
      await _load();
    } on Object {
      _persistenceBlocked = true;
      error = '会话读取失败，原有记录保留；开始新会话前不会覆盖';
      if (!_disposed) notifyListeners();
      rethrow;
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    final raw = await controller.readConversationState();
    if (raw == null || _disposed || generation != _generation) return;
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('会话版本不支持');
    final history = (data['history'] as List)
        .map((v) => Map<String, Object?>.from(v as Map))
        .toList();
    final tokens = Map<String, String>.from(data['tokens'] as Map);
    final loaded = <ConversationMessage>[];
    for (final raw in data['messages'] as List) {
      final suggestions = [
        for (final s in raw['suggestions'] as List)
          AiCardSuggestion(
            title: s['title'] as String,
            content: s['content'] as String,
            kind: CardKind.values.byName(s['kind'] as String),
            isInference: s['inference'] == true,
          ),
      ];
      loaded.add(
        ConversationMessage(
          raw['role'] as String,
          raw['text'] as String,
          suggestions: suggestions,
          reviewId: raw['reviewId'] as String,
          providerLabel: raw['providerLabel'] as String? ?? '',
          accepted: raw['accepted'] == true,
        ),
      );
    }
    final turn = data['turn'] as int;
    final provider = data['provider'] as String?;
    final loadedMarks = <int, SensitiveFieldKind>{
      for (final e in (data['marks'] as Map).entries)
        int.parse(e.key as String): SensitiveFieldKind.values.byName(
          e.value as String,
        ),
    };
    final loadedDraft = data['draft'] as String;
    _history.addAll(history);
    _tokens.addAll(tokens);
    messages.addAll(loaded);
    _turn = turn;
    _providerFingerprint = provider;
    draft = loadedDraft;
    marks.addAll(loadedMarks);
    notifyListeners();
  }

  Future<void> flush() {
    if (_persistenceBlocked) {
      return Future.error(const FormatException('会话记录无法读取，请先明确开始新会话'));
    }
    _saveTimer?.cancel();
    final generation = _generation;
    final state = jsonEncode({
      'version': 1,
      'turn': _turn,
      'provider': _providerFingerprint,
      'history': _history,
      'tokens': _tokens,
      'draft': draft,
      'marks': {for (final e in marks.entries) e.key.toString(): e.value.name},
      'messages': [
        for (final m in messages)
          {
            'role': m.role,
            'text': m.text,
            'reviewId': m.reviewId,
            'providerLabel': m.providerLabel,
            'accepted': m.accepted,
            'suggestions': [
              for (final s in m.suggestions)
                {
                  'title': s.title,
                  'content': s.content,
                  'kind': s.kind.name,
                  'inference': s.isInference,
                },
            ],
          },
      ],
    });
    final next = _writes.catchError((Object _) {}).then((_) async {
      if (!_disposed && generation == _generation && controller.isUnlocked) {
        await controller.writeConversationState(state);
      }
    });
    _writes = next;
    return next;
  }

  String _rehydrate(String text, Map<String, String> tokens) {
    for (final entry in tokens.entries) {
      text = text.replaceAll(entry.key, entry.value);
    }
    return text;
  }

  Future<bool> send(PreparedConversationTurn turn) async {
    if (working) return false;
    working = true;
    error = null;
    notifyListeners();
    final generation = _generation;
    final settings = controller.aiSettings;
    final fingerprint =
        '${settings.protocol.name}:${settings.endpoint}:${settings.model}';
    try {
      if (_persistenceBlocked ||
          turn.generation != _generation ||
          turn.turn != _turn ||
          turn.provider != fingerprint) {
        throw const FormatException('会话或服务配置已变化，请重新检查本轮发送范围');
      }
      if (_providerFingerprint != null && fingerprint != _providerFingerprint) {
        throw const FormatException('服务或模型已切换，请先开始新会话，避免将既有对话转发给其他模型');
      }
      final response = await controller.converse(
        turn.payload.redactedText,
        List.of(_history),
      );
      if (_disposed || generation != _generation || !controller.isUnlocked) {
        return false;
      }
      final raw = response.content
          .trim()
          .replaceFirst(RegExp(r'^```(?:json)?\s*'), '')
          .replaceFirst(RegExp(r'\s*```$'), '');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data.keys.toSet().difference({'reply', 'cards'}).isNotEmpty ||
          data['reply'] is! String ||
          data['cards'] is! List) {
        throw const FormatException('对话建议结构无效');
      }
      final tokens = {..._tokens, ...turn.payload.tokenMap};
      if (_pattern
          .allMatches(raw)
          .any((m) => !tokens.containsKey(m.group(0)))) {
        throw const FormatException('对话包含未知敏感占位符');
      }
      final cardsJson = jsonEncode({'cards': data['cards']});
      final used = _pattern
          .allMatches(cardsJson)
          .map((m) => m.group(0)!)
          .toSet();
      final suggestions = (data['cards'] as List).isEmpty
          ? <AiCardSuggestion>[]
          : const AiPrivacyProcessor().validateAndRehydrate(
              cardsJson,
              AiTokenizedPayload(
                redactedText: turn.payload.redactedText,
                tokenMap: {for (final t in used) t: tokens[t]!},
              ),
            );
      _history.add({'role': 'user', 'content': turn.payload.redactedText});
      _history.addAll(response.output);
      _tokens.addAll(turn.payload.tokenMap);
      _providerFingerprint = fingerprint;
      _turn++;
      messages.add(ConversationMessage('user', turn.text));
      messages.add(
        ConversationMessage(
          'assistant',
          _rehydrate(data['reply'] as String, tokens),
          suggestions: suggestions,
          providerLabel:
              '本人编辑并确认 · ${settings.model} · ${Uri.parse(settings.endpoint).host}',
        ),
      );
      if (draft == turn.text) {
        draft = '';
        marks.clear();
      }
      try {
        await flush();
      } on Object {
        error = '会话保存失败，内容仍保留；可以重试保存';
      }
      return true;
    } on Object catch (e) {
      if (!_disposed && generation == _generation) {
        error = e is FormatException
            ? e.message
            : controller.lastError ?? '对话失败，输入仍保留';
      }
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> retrySave() async {
    final generation = _generation;
    try {
      await flush();
      if (generation == _generation) error = null;
    } on Object {
      if (generation == _generation) error = '会话保存失败，内容仍保留';
    }
    if (!_disposed && generation == _generation) notifyListeners();
  }

  Future<void> accept(ConversationMessage message) async {
    if (working ||
        message.accepted ||
        !messages.contains(message) ||
        message.role != 'assistant') {
      return;
    }
    working = true;
    error = null;
    notifyListeners();
    final generation = _generation;
    try {
      // Persist the review identity before the atomic, idempotent card transaction.
      await flush();
      final previousInputs = messages
          .take(messages.indexOf(message))
          .where((m) => m.role == 'user');
      await controller.acceptConversationCards(
        message.reviewId,
        previousInputs.map((m) => m.text).join('\n'),
        message.suggestions,
        providerLabel: message.providerLabel,
      );
      if (_disposed || generation != _generation || !controller.isUnlocked) {
        return;
      }
      message.accepted = true;
      await flush();
    } on Object catch (e) {
      if (!_disposed && generation == _generation) {
        error = e is FormatException
            ? e.message
            : controller.lastError ?? '保存建议失败，可重试';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> newConversation() async {
    if (working) return;
    clear();
    _persistenceBlocked = false;
    await retrySave();
  }

  void clear() {
    _generation++;
    _saveTimer?.cancel();
    _history.clear();
    _tokens.clear();
    messages.clear();
    marks.clear();
    draft = '';
    _turn = 0;
    _providerFingerprint = null;
    error = null;
    working = false;
  }

  @override
  void dispose() {
    _disposed = true;
    controller.removeListener(_sessionChanged);
    controller.cancelAgentTask();
    clear();
    super.dispose();
  }
}
