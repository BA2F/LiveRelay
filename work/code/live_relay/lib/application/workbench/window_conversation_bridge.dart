import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../agent/agent_conversation.dart';
import '../../core/ai/conversation_attachment.dart';
import '../../core/ai/review_actions.dart';
import '../../core/domain/entities.dart';

Map<String, Object?> windowSuggestion(ConversationMessage message) => {
  'role': message.role,
  'text': message.text,
  'reviewId': message.reviewId,
  'accepted': message.accepted,
  'actions': [for (final plan in message.actions) plan.toJson()],
  'proposals': [for (final proposal in message.proposals) proposal?.toJson()],
  'suggestions': [
    for (final s in message.suggestions)
      {
        'title': s.title,
        'content': s.content,
        'kind': s.kind.name,
        'inference': s.isInference,
        'tags': s.tags,
      },
  ],
};

String windowReviewStamp(ConversationMessage message) => sha256
    .convert(utf8.encode(jsonEncode(windowSuggestion(message))))
    .toString();

Map<String, Object?> windowAttachment(
  ConversationAttachment a, {
  bool bytes = false,
}) => {
  'id': a.id,
  'name': a.name,
  'kind': a.kind.name,
  'mime': a.mimeType,
  'card': a.cardId,
  'cardRevision': a.cardRevision,
  'blob': a.blobId,
  'size': a.bytes.length,
  if (bytes) 'bytes': Uint8List.fromList(a.bytes),
  'transcript': a.transcript,
  'sendDescription': a.sendDescription,
  'audioStamp': a.audioStamp,
  if (bytes && a.normalizedAudio != null)
    'normalizedAudio': Uint8List.fromList(a.normalizedAudio!),
  'frames': [
    for (final frame in a.frames)
      {
        'ms': frame.milliseconds,
        if (bytes) 'bytes': Uint8List.fromList(frame.bytes),
      },
  ],
};

/// One authenticated child binding to the main-owned conversation. It exposes
/// presentation state and explicit owner commands, never configuration keys or
/// privacy token maps. Prepared uploads are private and single-use.
class WindowConversationBridge {
  WindowConversationBridge(this.conversation, {required this.active});
  final AgentConversation conversation;
  final bool Function() active;
  PreparedConversationTurn? _prepared;
  String? _ticket, _preparedStamp;
  static const methods = {
    'draft',
    'mark',
    'prepareSend',
    'send',
    'cancelSend',
    'cancelAgent',
    'newConversation',
    'selectModel',
    'editSuggestion',
    'editActions',
    'adoptProposal',
    'accept',
    'addFiles',
    'attachCard',
    'attachOriginal',
    'removeAttachment',
    'saveAttachment',
    'readAttachment',
    'videoFrames',
    'attachmentAudio',
    'attachmentTranscript',
  };
  void clear() {
    _prepared = null;
    _ticket = null;
    _preparedStamp = null;
  }

  void _check({bool idle = false}) {
    if (!active() || !conversation.controller.isUnlocked) {
      throw PlatformException(code: 'SESSION_REVOKED');
    }
    if (idle && conversation.working) {
      throw const FormatException('助手正在处理，请先停止');
    }
  }

  String get stamp => sha256
      .convert(
        utf8.encode(
          jsonEncode({
            'draft': conversation.draft,
            'marks': {
              for (final e in conversation.marks.entries)
                '${e.key}': e.value.name,
            },
            'attachments': [
              for (final a in conversation.attachments) windowAttachment(a),
            ],
            'messages': [
              for (final m in conversation.messages) windowReviewStamp(m),
            ],
            'configuration': conversation.controller.aiConfigurationGeneration,
          }),
        ),
      )
      .toString();

  Map<String, Object?> snapshot() => {
    'draft': conversation.draft,
    'working': conversation.working,
    'model': conversation.controller.aiSettings.model,
    'profile': conversation.controller.aiSettings.id,
    'models': [
      for (final p in conversation.controller.aiProfiles)
        for (final model in p.models)
          {'id': p.id, 'name': p.name, 'model': model},
    ],
    'marks': {
      for (final e in conversation.marks.entries) '${e.key}': e.value.name,
    },
    'error': conversation.error,
    'conversationStamp': stamp,
    'attachments': [
      for (final a in conversation.attachments) windowAttachment(a),
    ],
    'messages': [
      for (final m in conversation.messages)
        {
          ...windowSuggestion(m),
          'stamp': windowReviewStamp(m),
          'attachments': [for (final a in m.attachments) windowAttachment(a)],
        },
    ],
    'targets': [
      for (final c in conversation.controller.cards)
        {
          'id': c.id,
          'title': c.title,
          'content': c.content,
          'kind': c.kind.name,
        },
    ],
    'originals': [
      for (final b in conversation.controller.blobs)
        if (!conversation.controller.recycledBlobIds.contains(b.id))
          {'id': b.id, 'name': b.originalName},
    ],
  };

  Future<Object?> invoke(MethodCall call) async {
    _check();
    final c = conversation, controller = c.controller;
    final a = call.arguments is Map ? call.arguments as Map : const {};
    ConversationMessage message() =>
        c.messages.where((m) => m.reviewId == a['reviewId']).firstOrNull ??
        (throw const FormatException('建议已失效'));
    ConversationAttachment attachment({bool current = true}) =>
        [
          ...c.attachments,
          if (!current) ...c.messages.expand((m) => m.attachments),
        ].where((item) => item.id == a['id']).firstOrNull ??
        (throw const FormatException('附件已移除'));
    int index(ConversationMessage m) {
      final value = a['index'];
      if (value is! int || value < 0 || value >= m.suggestions.length) {
        throw const FormatException('建议字段无效');
      }
      return value;
    }

    void unchanged() {
      if (a['stamp'] != stamp) throw const FormatException('会话已变化，请重新核对');
    }

    switch (call.method) {
      case 'draft':
        _check(idle: true);
        if (a['text'] is! String || (a['text'] as String).length > 32000) {
          throw const FormatException('输入过长');
        }
        c.updateDraft(a['text'] as String);
      case 'mark':
        _check(idle: true);
        final line = a['line'];
        if (line is! int || line < 0 || line >= c.draft.split('\n').length) {
          throw const FormatException('敏感行已失效');
        }
        c.mark(
          line,
          a['kind'] == null
              ? null
              : SensitiveFieldKind.values.byName(a['kind'] as String),
        );
      case 'prepareSend':
        _check(idle: true);
        clear();
        final turn = c.prepare(c.draft, [
          for (final e in c.marks.entries)
            SensitiveMark(lineOrder: e.key, kind: e.value),
        ]);
        _prepared = turn;
        _preparedStamp = stamp;
        _ticket = const Uuid().v7();
        return {
          'ticket': _ticket,
          'text': turn.payload.redactedText,
          'history': c.disclosureHistory,
          'model': controller.aiSettings.model,
          'host': Uri.tryParse(controller.aiSettings.endpoint)?.host ?? '尚未配置',
          'targets': [for (final target in turn.reviewTargets) target.toJson()],
          'attachments': [
            for (final item in turn.attachments) windowAttachment(item),
          ],
        };
      case 'cancelSend':
        clear();
      case 'send':
        _check(idle: true);
        final turn = _prepared;
        final valid =
            turn != null && a['ticket'] == _ticket && stamp == _preparedStamp;
        clear();
        if (!valid) throw const FormatException('外发范围已变化，请重新核对');
        unawaited(c.send(turn));
        return true;
      case 'cancelAgent':
        controller.cancelAgentTask();
      case 'newConversation':
        _check(idle: true);
        unchanged();
        clear();
        await c.newConversation();
      case 'selectModel':
        _check(idle: true);
        unchanged();
        clear();
        final id = a['id'], model = a['model'];
        if (!controller.aiProfiles.any(
          (p) => p.id == id && p.models.contains(model),
        )) {
          throw const FormatException('服务或模型已失效');
        }
        await controller.selectAiProfile(id as String, model as String);
        _check(idle: true);
        await c.newConversation();
      case 'editSuggestion':
        _check(idle: true);
        final m = message(), i = index(message());
        final value = a['suggestion'];
        const fields = {'title', 'content', 'tags', 'kind', 'inference'};
        if (value is! Map ||
            value.isEmpty ||
            value.keys.any((k) => !fields.contains(k)) ||
            ['title', 'content'].any(
              (k) =>
                  value.containsKey(k) &&
                  (value[k] is! String || (value[k] as String).length > 32000),
            ) ||
            (value.containsKey('tags') &&
                (value['tags'] is! List ||
                    (value['tags'] as List).length > 200 ||
                    (value['tags'] as List).any(
                      (t) => t is! String || t.length > 240,
                    ))) ||
            (value.containsKey('inference') && value['inference'] is! bool)) {
          throw const FormatException('建议字段无效');
        }
        final kind = value['kind'] == null
            ? null
            : CardKind.values.byName(value['kind'] as String);
        if (kind == CardKind.bundle) throw const FormatException('建议类型无效');
        c.editSuggestion(
          m,
          i,
          title: value['title'] as String?,
          content: value['content'] as String?,
          kind: kind,
          isInference: value['inference'] as bool?,
          tags: (value['tags'] as List?)?.cast<String>(),
        );
      case 'editActions':
        _check(idle: true);
        final m = message();
        c.editActions(m, index(m), ReviewActions.fromJson(a['plan'] as Map));
      case 'adoptProposal':
        _check(idle: true);
        final m = message();
        c.adoptProposal(m, index(m));
      case 'accept':
        _check(idle: true);
        final m = message();
        if (a['stamp'] != windowReviewStamp(m)) {
          throw const FormatException('建议或操作计划已变化，请重新核对');
        }
        await c.accept(m);
      case 'addFiles':
        _check(idle: true);
        final paths = a['paths'];
        if (paths is! List ||
            paths.length > 6 ||
            paths.any(
              (p) => p is! String || p.length > 4096 || !File(p).isAbsolute,
            )) {
          throw const FormatException('附件选择无效');
        }
        await c.addFilePaths(paths.cast<String>());
      case 'attachCard':
        _check(idle: true);
        final card = controller.cards
            .where((item) => item.id == a['id'])
            .firstOrNull;
        if (card == null) throw const FormatException('卡片已失效');
        c.attachCard(card);
      case 'attachOriginal':
        _check(idle: true);
        final blob = controller.blobs
            .where(
              (item) =>
                  item.id == a['id'] &&
                  !controller.recycledBlobIds.contains(item.id),
            )
            .firstOrNull;
        if (blob == null) throw const FormatException('原件已失效');
        await c.attachOriginal(blob);
      case 'removeAttachment':
        _check(idle: true);
        c.removeAttachment(attachment());
      case 'saveAttachment':
        _check(idle: true);
        await c.saveOriginal(attachment(current: false));
      case 'readAttachment':
        return windowAttachment(attachment(current: false), bytes: true);
      case 'attachmentAudio':
        _check(idle: true);
        final wav = a['wav'];
        if (wav != null && wav is! Uint8List) {
          throw const FormatException('音轨无效');
        }
        c.setAttachmentAudio(
          attachment(),
          wav == null ? null : Uint8List.fromList(wav as Uint8List),
        );
      case 'attachmentTranscript':
        _check(idle: true);
        final text = a['text'];
        if (text != null && text is! String) {
          throw const FormatException('转写无效');
        }
        c.setAttachmentTranscript(attachment(), text as String?);
      case 'videoFrames':
        _check(idle: true);
        final item = attachment(), values = a['frames'];
        if (item.kind != ConversationAttachmentKind.video ||
            values is! List ||
            values.isEmpty ||
            values.length > 4 ||
            values.any(
              (v) =>
                  v is! Map ||
                  v['ms'] is! int ||
                  v['ms'] < 0 ||
                  v['ms'] > 600000 ||
                  v['bytes'] is! Uint8List ||
                  (v['bytes'] as Uint8List).isEmpty ||
                  (v['bytes'] as Uint8List).length > 256 * 1024,
            )) {
          throw const FormatException('视频帧无效');
        }
        c.replaceVideoFrames(item, [
          for (final v in values)
            (
              milliseconds: v['ms'] as int,
              bytes: Uint8List.fromList(v['bytes'] as Uint8List),
            ),
        ]);
      default:
        throw PlatformException(code: 'UNSUPPORTED_COMMAND');
    }
    _check();
    return true;
  }
}
