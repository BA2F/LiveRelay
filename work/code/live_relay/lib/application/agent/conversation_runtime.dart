import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/ai/conversation_attachment.dart';
import '../../core/media/pcm_wave.dart';
import '../../core/ai/review_source.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/review_action_proposal.dart';

import 'dart:typed_data';

import 'conversation_application.dart';
import '../../core/ai/conversation_state.dart';
import '../../core/ai/ai_privacy.dart';
import '../../core/domain/entities.dart';

/// One encrypted conversation per vault; view lifetimes do not own its contents.
class ConversationRuntime {
  ConversationRuntime(this.application) {
    _subscriptions = [
      application.vault.changes.listen((_) => _sessionChanged()),
      application.settings.changes.listen((_) => _sessionChanged()),
      application.snapshots.changes.listen((_) => _sessionChanged()),
    ];
  }
  late final List<StreamSubscription<Object?>> _subscriptions;
  final _changes = StreamController<void>.broadcast();
  Stream<void> get changes => _changes.stream;
  void _changed() {
    if (!_disposed) _changes.add(null);
  }

  void _sessionChanged() {
    if (!application.isUnlocked) {
      clear();
      if (!_disposed) _changed();
    } else if (!_disposed) {
      _changed();
    }
  }

  String get _configuration {
    final s = application.aiSettings;
    return '${s.id}:${s.protocol.name}:${s.endpoint}:${s.model}:${s.supportsImages}:${s.supportsFiles}:${s.supportsAudio}';
  }

  final ConversationApplication application;
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
    final settings = application.aiSettings;
    for (final a in selected) {
      a.wireParts(
        settings.protocol,
        images: settings.supportsImages,
        files: settings.supportsFiles,
        audio: settings.supportsAudio,
      );
    }
    final input = text.trim().isEmpty && selected.isNotEmpty
        ? '请理解所选附件。'
        : text;
    final payload = application.prepareConversationText(input, marks);
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
      application.aiConfigurationGeneration,
      List.unmodifiable([
        for (final id
            in selected.map((a) => a.cardId).whereType<String>().toSet())
          for (final card in application.cards.where((c) => c.id == id))
            ReviewTarget(id, bundle: card.kind == CardKind.bundle),
      ]),
    );
  }

  String get disclosureHistory {
    Object? preview(Object? value) {
      if (value is List) return value.map(preview).toList();
      if (value is Map) {
        return {
          for (final entry in value.entries)
            entry.key:
                entry.key == 'data' && {'wav', 'mp3'}.contains(value['format'])
                ? '[完整音频；见历史附件预览]'
                : preview(entry.value),
        };
      }
      return value;
    }

    return jsonEncode(preview(_history)).replaceAll(
      RegExp(r'data:[^;]+;base64,[A-Za-z0-9+/=]+'),
      '[附件二进制；见历史附件预览]',
    );
  }

  String get attachmentStamp => attachments.map((a) => a.id).join(',');
  Future<void> addFilePaths(Iterable<String> paths) async {
    if (working || !application.isUnlocked) return;
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
      if (_disposed || generation != _generation || !application.isUnlocked) {
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
    _changed();
  }

  void attachCard(LifeCard card) {
    if (working || !application.isUnlocked) return;
    _addAttachments([
      ConversationAttachment.read(
        '${card.title}.txt',
        Uint8List.fromList(utf8.encode('${card.title}\n${card.content}')),
        cardId: card.id,
        cardRevision: card.revisionNumber,
      ),
    ]);
  }

  Future<void> attachOriginal(VaultBlob blob) async {
    if (working || !application.isUnlocked) return;
    if (blob.byteLength > ConversationAttachment.maxBytes) {
      throw const FormatException('每个附件最多 2 MB');
    }
    final generation = _generation;
    final bytes = await application.readOriginal(blob.id);
    if (_disposed || generation != _generation || !application.isUnlocked) {
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

  void replaceVideoFrames(
    ConversationAttachment attachment,
    List<({int milliseconds, Uint8List bytes})> frames,
  ) {
    if (working ||
        !application.isUnlocked ||
        !attachments.contains(attachment)) {
      for (final f in frames) {
        f.bytes.fillRange(0, f.bytes.length, 0);
      }
      return;
    }
    if (frames.isEmpty ||
        frames.length > 4 ||
        frames.any((f) => f.bytes.length > 256 * 1024)) {
      for (final f in frames) {
        f.bytes.fillRange(0, f.bytes.length, 0);
      }
      throw const FormatException('视频最多4帧，每帧256KB');
    }
    for (final f in attachment.frames) {
      f.bytes.fillRange(0, f.bytes.length, 0);
    }
    attachment.frames
      ..clear()
      ..addAll(frames);
    _generation++;
    _scheduleSave();
    _changed();
  }

  void setAttachmentAudio(ConversationAttachment attachment, Uint8List? wav) {
    if (working ||
        !application.isUnlocked ||
        !attachments.contains(attachment) ||
        !{
          ConversationAttachmentKind.audio,
          ConversationAttachmentKind.video,
        }.contains(attachment.kind)) {
      wav?.fillRange(0, wav.length, 0);
      throw const FormatException('附件已变化');
    }
    try {
      if (wav != null) PcmWave.validate(wav);
    } on Object {
      wav?.fillRange(0, wav.length, 0);
      rethrow;
    }
    attachment.normalizedAudio?.fillRange(
      0,
      attachment.normalizedAudio!.length,
      0,
    );
    attachment.normalizedAudio = wav;
    attachment.transcript = null;
    _generation++;
    _scheduleSave();
    _changed();
  }

  void setAttachmentTranscript(
    ConversationAttachment attachment,
    String? text,
  ) {
    if (working ||
        !application.isUnlocked ||
        !attachments.contains(attachment) ||
        !{
          ConversationAttachmentKind.audio,
          ConversationAttachmentKind.video,
        }.contains(attachment.kind) ||
        (text != null && (text.trim().isEmpty || text.length > 32000))) {
      throw const FormatException('附件转写无效');
    }
    attachment.transcript = text?.trim();
    _generation++;
    _scheduleSave();
    _changed();
  }

  void removeAttachment(ConversationAttachment attachment) {
    if (working || !attachments.remove(attachment)) return;
    attachment.wipe();
    _scheduleSave();
    _changed();
  }

  Future<void> saveOriginal(ConversationAttachment attachment) async {
    if (working || attachment.blobId != null || attachment.cardId != null) {
      return;
    }
    working = true;
    _changed();
    try {
      final original = await application.importOriginal(
        bytes: Uint8List.fromList(attachment.bytes),
        originalName: attachment.name,
        mimeType: attachment.mimeType,
        mediaKind: switch (attachment.kind) {
          ConversationAttachmentKind.image => BlobMediaKind.image,
          ConversationAttachmentKind.audio => BlobMediaKind.audio,
          ConversationAttachmentKind.video => BlobMediaKind.video,
          _ => BlobMediaKind.document,
        },
      );
      attachment.blobId = (await application.cardSources(original.id))
          .first
          .blobId;
      await flush();
    } finally {
      if (!_disposed) {
        working = false;
        _changed();
      }
    }
  }

  void updateDraft(String text) {
    draft = text;
    marks.removeWhere((line, _) => line >= text.split('\n').length);
    _scheduleSave();
    _changed();
  }

  void mark(int line, SensitiveFieldKind? kind) {
    if (kind == null) {
      marks.remove(line);
    } else {
      marks[line] = kind;
    }
    _scheduleSave();
    _changed();
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
    _changed();
  }

  void editActions(
    ConversationMessage message,
    int index,
    ReviewActions actions,
  ) {
    if (message.accepted || working || !messages.contains(message)) return;
    if (index < 0 || index >= message.suggestions.length) {
      throw const FormatException('建议已失效');
    }
    actions.validate();
    message.actions[index] = actions;
    _scheduleSave();
    _changed();
  }

  void adoptProposal(ConversationMessage message, int index) {
    if (message.accepted || working || !messages.contains(message)) return;
    if (index < 0 || index >= message.proposals.length) {
      throw const FormatException('操作草案已失效');
    }
    final proposal = message.proposals[index];
    if (proposal == null) return;
    editActions(message, index, proposal.plan);
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
      if (!_disposed) _changed();
      rethrow;
    }
  }

  Future<void> _load() async {
    final generation = _generation;
    final raw = await application.readConversationState();
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
          actions: raw['actions'] == null
              ? null
              : [
                  for (final a in raw['actions'] as List)
                    ReviewActions.fromJson(a as Map),
                ],
          proposals: raw['proposals'] == null
              ? null
              : [
                  for (final proposal in raw['proposals'] as List)
                    proposal == null
                        ? null
                        : ReviewActionProposal.fromJson(proposal as Map),
                ],
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
    final settings = application.aiSettings;
    final oldConfiguration =
        '${settings.protocol.name}:${settings.endpoint}:${settings.model}';
    final withCapabilities =
        '$oldConfiguration:${settings.supportsImages}:${settings.supportsFiles}';
    _providerFingerprint = provider == oldConfiguration
        ? '${settings.id}:$provider:false:false:false'
        : provider == withCapabilities
        ? '${settings.id}:$provider:false'
        : provider == '${settings.id}:$withCapabilities'
        ? '$provider:false'
        : provider;
    draft = loadedDraft;
    marks.addAll(loadedMarks);
    _changed();
  }

  /// Finish existing autosaves before another view takes the shared write gate.
  /// With no pending edits this does not create/overwrite a conversation record.
  Future<void> finishPendingSave() =>
      _saveTimer?.isActive == true ? flush() : _writes;

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
            'actions': [for (final a in m.actions) a.toJson()],
            'proposals': [for (final p in m.proposals) p?.toJson()],
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
      if (!_disposed && generation == _generation && application.isUnlocked) {
        await application.writeConversationState(state);
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
    _changed();
    final generation = _generation;
    final settings = application.aiSettings;
    final fingerprint = _configuration;
    try {
      if (_persistenceBlocked ||
          turn.generation != _generation ||
          turn.turn != _turn ||
          turn.provider != fingerprint ||
          turn.configurationGeneration !=
              application.aiConfigurationGeneration ||
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
                ...a.wireParts(
                  settings.protocol,
                  images: settings.supportsImages,
                  files: settings.supportsFiles,
                  audio: settings.supportsAudio,
                ),
            ];
      final response = await application.converse(
        turn.payload.redactedText,
        List.of(_history),
        inputContent: content,
        reviewTargets: turn.reviewTargets,
      );
      if (_disposed || generation != _generation || !application.isUnlocked) {
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
      final proposals = <ReviewActionProposal?>[];
      final draftCards = <Map<String, Object?>>[];
      for (final item in data['cards'] as List) {
        if (item is! Map ||
            item.keys.toSet().difference({
              'title',
              'content',
              'kind',
              'inference',
              'actions',
            }).isNotEmpty) {
          throw const FormatException('对话建议字段无效');
        }
        final proposed = item['actions'];
        if (proposed != null && proposed is! Map) {
          throw const FormatException('模型操作草案结构无效');
        }
        proposals.add(
          proposed == null
              ? null
              : ReviewActionProposal.parse(proposed as Map, turn.reviewTargets),
        );
        draftCards.add({
          for (final entry in item.entries)
            if (entry.key != 'actions') entry.key as String: entry.value,
        });
      }
      final cardsJson = jsonEncode({'cards': draftCards});
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
          proposals: proposals,
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
        error = e is FormatException ? e.message : '对话失败，输入仍保留';
      }
      return false;
    } finally {
      if (!_disposed && generation == _generation) {
        working = false;
        _changed();
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
    if (!_disposed && generation == _generation) _changed();
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
    _changed();
    final generation = _generation;
    try {
      // Persist the review identity before the atomic, idempotent card transaction.
      await flush();
      final previousInputs = messages
          .take(messages.indexOf(message))
          .where((m) => m.role == 'user')
          .toList();
      await application.acceptConversationCards(
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
        actions: List.of(message.actions),
        reviewSource: ReviewSource(
          reviewId: message.reviewId,
          providerLabel: message.providerLabel,
          confirmedAt: DateTime.now().toUtc(),
          inputs: [
            for (final input in previousInputs)
              ReviewSourceInput(input.text, input.attachments),
          ],
          reply: message.text,
          actions: List.of(message.actions),
          proposals: List.of(message.proposals),
        ),
        originalIds: previousInputs
            .expand((m) => m.attachments)
            .map((a) => a.blobId)
            .whereType<String>()
            .toSet()
            .toList(),
      );
      if (_disposed || generation != _generation || !application.isUnlocked) {
        return;
      }
      // A crash after commit may leave an unaccepted conversation message.
      // Retry restores the first transaction's choices rather than claiming
      // that later edits changed an already committed receipt.
      final applied = await application.reviewedActions(message.reviewId);
      if (_disposed || generation != _generation || !application.isUnlocked) {
        return;
      }
      final plans = applied == null || applied.isEmpty
          ? List.generate(
              message.suggestions.length,
              (_) => const ReviewActions(),
            )
          : applied;
      if (plans.length != message.suggestions.length) {
        throw const FormatException('已确认计划数量不匹配');
      }
      message.actions
        ..clear()
        ..addAll(plans);
      message.accepted = true;
      await flush();
    } on Object catch (e) {
      if (!_disposed && generation == _generation) {
        error = e is FormatException ? e.message : '保存建议失败，可重试';
      }
    } finally {
      if (!_disposed && generation == _generation) {
        working = false;
        _changed();
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

  void dispose() {
    _disposed = true;
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    application.cancelAgentTask();
    clear();
    unawaited(_changes.close());
  }
}
