import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/ai/conversation_attachment.dart';

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
    this.attachments,
    this.configurationGeneration,
  );
  final List<ConversationAttachment> attachments;
  final int generation, turn;
  final int configurationGeneration;
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
    this.attachments = const [],
    this.accepted = false,
  }) : suggestions = List.of(suggestions),
       reviewId = reviewId ?? const Uuid().v7();
  final List<ConversationAttachment> attachments;
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
    } else if (!_disposed) {
      notifyListeners();
    }
  }

  String get _configuration {
    final s = controller.aiSettings;
    return '${s.id}:${s.protocol.name}:${s.endpoint}:${s.model}:${s.supportsImages}:${s.supportsFiles}';
  }

  final AppController controller;
  final messages = <ConversationMessage>[];
  final attachments = <ConversationAttachment>[];
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
    final selected = List<ConversationAttachment>.of(attachments);
    final settings = controller.aiSettings;
    for (final a in selected) {
      a.wire(
        settings.protocol,
        images: settings.supportsImages,
        files: settings.supportsFiles,
      );
    }
    final input = text.trim().isEmpty && selected.isNotEmpty
        ? '请理解所选附件。'
        : text;
    final payload = controller.prepareConversationText(input, marks);
    var redacted = payload.redactedText;
    final tokens = <String, String>{};
    for (final entry in payload.tokenMap.entries) {
      final token = '[[TURN${_turn + 1}_${entry.key.substring(2)}';
      redacted = redacted.replaceAll(entry.key, token);
      tokens[token] = entry.value;
    }
    return PreparedConversationTurn(
      input,
      AiTokenizedPayload(redactedText: redacted, tokenMap: tokens),
      _generation,
      _turn,
      _configuration,
      selected,
      controller.aiConfigurationGeneration,
    );
  }

  String get disclosureHistory => jsonEncode(
    _history,
  ).replaceAll(RegExp(r'data:[^;]+;base64,[A-Za-z0-9+/=]+'), '[附件二进制；见历史附件预览]');
  String get attachmentStamp => attachments.map((a) => a.id).join(',');
  Future<void> addFilePaths(Iterable<String> paths) async {
    if (working || !controller.isUnlocked) return;
    final generation = _generation;
    final added = <ConversationAttachment>[];
    try {
      for (final filePath in paths) {
        final file = File(filePath);
        if (await file.length() > ConversationAttachment.maxBytes) {
          throw const FormatException('每个附件最多 2 MB');
        }
        added.add(
          ConversationAttachment.read(
            path.basename(filePath),
            await file.readAsBytes(),
          ),
        );
      }
      if (_disposed || generation != _generation || !controller.isUnlocked) {
        for (final a in added) {
          a.wipe();
        }
        return;
      }
      _addAttachments(added);
    } on Object {
      for (final a in added) {
        a.wipe();
      }
      rethrow;
    }
  }

  void _addAttachments(List<ConversationAttachment> added) {
    if (attachments.length + added.length > 6 ||
        [...attachments, ...added].fold<int>(0, (n, a) => n + a.bytes.length) >
            4 * 1024 * 1024) {
      throw const FormatException('每轮最多 6 个附件、总计 4 MB');
    }
    attachments.addAll(added);
    _scheduleSave();
    notifyListeners();
  }

  void attachCard(LifeCard card) {
    if (working || !controller.isUnlocked) return;
    _addAttachments([
      ConversationAttachment.read(
        '${card.title}.txt',
        Uint8List.fromList(utf8.encode('${card.title}\n${card.content}')),
        cardId: card.id,
      ),
    ]);
  }

  Future<void> attachOriginal(VaultBlob blob) async {
    if (working || !controller.isUnlocked) return;
    if (blob.byteLength > ConversationAttachment.maxBytes) {
      throw const FormatException('每个附件最多 2 MB');
    }
    final generation = _generation;
    final bytes = await controller.readOriginal(blob.id);
    if (_disposed || generation != _generation || !controller.isUnlocked) {
      bytes.fillRange(0, bytes.length, 0);
      return;
    }
    try {
      _addAttachments([
        ConversationAttachment.read(blob.originalName, bytes, blobId: blob.id),
      ]);
    } on Object {
      bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }

  void removeAttachment(ConversationAttachment attachment) {
    if (working || !attachments.remove(attachment)) return;
    attachment.wipe();
    _scheduleSave();
    notifyListeners();
  }

  Future<void> saveOriginal(ConversationAttachment attachment) async {
    if (working || attachment.blobId != null || attachment.cardId != null) {
      return;
    }
    working = true;
    notifyListeners();
    try {
      final original = await controller.importOriginal(
        bytes: Uint8List.fromList(attachment.bytes),
        originalName: attachment.name,
        mimeType: attachment.mimeType,
        mediaKind: attachment.kind == ConversationAttachmentKind.image
            ? BlobMediaKind.image
            : BlobMediaKind.document,
      );
      attachment.blobId = (await controller.cardSources(original.id))
          .first
          .blobId;
      await flush();
    } finally {
      if (!_disposed) {
        working = false;
        notifyListeners();
      }
    }
  }

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
    CardKind? kind,
    bool? isInference,
    List<String>? tags,
  }) {
    if (message.accepted || working) return;
    final s = message.suggestions[index];
    message.suggestions[index] = AiCardSuggestion(
      title: title ?? s.title,
      content: content ?? s.content,
      kind: kind ?? s.kind,
      isInference: isInference ?? s.isInference,
      tags: tags ?? s.tags,
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
            tags: List<String>.from(s['tags'] as List? ?? []),
          ),
      ];
      loaded.add(
        ConversationMessage(
          raw['role'] as String,
          raw['text'] as String,
          suggestions: suggestions,
          reviewId: raw['reviewId'] as String,
          providerLabel: raw['providerLabel'] as String? ?? '',
          attachments: [
            for (final a in raw['attachments'] as List? ?? [])
              ConversationAttachment.fromJson(a as Map),
          ],
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
    final loadedAttachments = [
      for (final a in data['attachments'] as List? ?? [])
        ConversationAttachment.fromJson(a as Map),
    ];
    final loadedDraft = data['draft'] as String;
    _history.addAll(history);
    _tokens.addAll(tokens);
    messages.addAll(loaded);
    attachments.addAll(loadedAttachments);
    _turn = turn;
    final settings = controller.aiSettings;
    final oldConfiguration =
        '${settings.protocol.name}:${settings.endpoint}:${settings.model}';
    final withCapabilities =
        '$oldConfiguration:${settings.supportsImages}:${settings.supportsFiles}';
    _providerFingerprint = provider == oldConfiguration
        ? '${settings.id}:$provider:false:false'
        : provider == withCapabilities
        ? '${settings.id}:$provider'
        : provider;
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
      'attachments': [for (final a in attachments) a.toJson()],
      'marks': {for (final e in marks.entries) e.key.toString(): e.value.name},
      'messages': [
        for (final m in messages)
          {
            'role': m.role,
            'text': m.text,
            'reviewId': m.reviewId,
            'providerLabel': m.providerLabel,
            'attachments': [for (final a in m.attachments) a.toJson()],
            'accepted': m.accepted,
            'suggestions': [
              for (final s in m.suggestions)
                {
                  'title': s.title,
                  'content': s.content,
                  'kind': s.kind.name,
                  'inference': s.isInference,
                  'tags': s.tags,
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
    final fingerprint = _configuration;
    try {
      if (_persistenceBlocked ||
          turn.generation != _generation ||
          turn.turn != _turn ||
          turn.provider != fingerprint ||
          turn.configurationGeneration !=
              controller.aiConfigurationGeneration ||
          turn.attachments.map((a) => a.id).join(',') != attachmentStamp) {
        throw const FormatException('会话或服务配置已变化，请重新检查本轮发送范围');
      }
      if (_providerFingerprint != null && fingerprint != _providerFingerprint) {
        throw const FormatException('服务或模型已切换，请先开始新会话，避免将既有对话转发给其他模型');
      }
      final content = turn.attachments.isEmpty
          ? null
          : <Map<String, Object?>>[
              {
                'type': settings.protocol.name == 'responses'
                    ? 'input_text'
                    : 'text',
                'text': turn.payload.redactedText,
              },
              for (final a in turn.attachments)
                a.wire(
                  settings.protocol,
                  images: settings.supportsImages,
                  files: settings.supportsFiles,
                ),
            ];
      final response = await controller.converse(
        turn.payload.redactedText,
        List.of(_history),
        inputContent: content,
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
      _history.add({
        'role': 'user',
        'content': content ?? turn.payload.redactedText,
      });
      _history.addAll(response.output);
      _tokens.addAll(turn.payload.tokenMap);
      _providerFingerprint = fingerprint;
      _turn++;
      messages.add(
        ConversationMessage('user', turn.text, attachments: turn.attachments),
      );
      attachments.clear();
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
        previousInputs
            .map(
              (m) =>
                  m.text +
                  (m.attachments.isEmpty
                      ? ''
                      : '\n附件：${m.attachments.map((a) => a.name).join(', ')}'),
            )
            .join('\n'),
        message.suggestions,
        providerLabel: message.providerLabel,
        originalIds: previousInputs
            .expand((m) => m.attachments)
            .map((a) => a.blobId)
            .whereType<String>()
            .toSet()
            .toList(),
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
    for (final a in [
      ...attachments,
      ...messages.expand((m) => m.attachments),
    ]) {
      a.wipe();
    }
    attachments.clear();
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
