import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/agent/agent_conversation.dart';
import '../../application/preview_session.dart';
import '../../application/speech_input_binding.dart';
import '../../core/ai/ai_privacy.dart';
import '../../core/ai/conversation_attachment.dart';
import '../../core/ai/review_actions.dart';
import '../../core/ai/review_action_proposal.dart';
import '../../core/domain/entities.dart';
import 'attachment_strip.dart';
import 'review_actions_editor.dart';
import 'suggestion_review_editor.dart';

class DetachedConversationView extends StatefulWidget {
  const DetachedConversationView({
    super.key,
    required this.data,
    required this.session,
    required this.act,
    required this.request,
    required this.openSettings,
    required this.openSpeech,
    required this.openManual,
    this.speechBinding,
    this.openSpeechSettings,
  });
  final SpeechInputBinding? speechBinding;
  final VoidCallback? openSpeechSettings;
  final Map data;
  final PreviewSession session;
  final Future<void> Function(String, Map<String, Object?>) act;
  final Future<Object?> Function(String, Map<String, Object?>) request;
  final VoidCallback openSettings, openSpeech, openManual;
  @override
  State<DetachedConversationView> createState() =>
      _DetachedConversationViewState();
}

class _DetachedConversationViewState extends State<DetachedConversationView> {
  bool _closed = false, _hover = false;
  final _messageScroll = ScrollController();
  final _reads = <Future<void>>{};
  final _dialogs = <Route<dynamic>>{};
  bool get _working => widget.data['working'] == true;
  bool get _active => mounted && !_closed && widget.session.isUnlocked;
  List<Map> get _attachments =>
      (widget.data['attachments'] as List? ?? []).cast<Map>();
  List<LifeCard> get _targets => [
    for (final value in widget.data['targets'] as List? ?? [])
      LifeCard(
        id: value['id'] as String,
        title: value['title'] as String,
        content: value['content'] as String,
        kind: CardKind.values.byName(value['kind'] as String),
        status: CardStatus.confirmed,
        tags: const [],
        createdAt: DateTime(1970),
        updatedAt: DateTime(1970),
        revisionNumber: 1,
      ),
  ];
  @override
  void initState() {
    super.initState();
    widget.session.registerPreviewCleanup(_close);
    _showLatest();
  }

  void _showLatest() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_active && _messageScroll.hasClients) {
      _messageScroll.jumpTo(_messageScroll.position.maxScrollExtent);
    }
  });
  @override
  void didUpdateWidget(covariant DetachedConversationView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.data['messages'] as List? ?? []).length !=
        (widget.data['messages'] as List? ?? []).length) {
      _showLatest();
    }
  }

  Future<void> _close() async {
    _closed = true;
    for (final dialog in List.of(_dialogs).reversed) {
      if (dialog.isActive) {
        dialog.navigator?.removeRoute(dialog);
      }
    }
    _dialogs.clear();
    await Future.wait([
      for (final read in List.of(_reads)) read.catchError((Object _) {}),
    ]);
    widget.session.unregisterPreviewCleanup(_close);
  }

  @override
  void dispose() {
    unawaited(_close());
    _messageScroll.dispose();
    super.dispose();
  }

  Future<void> _errorAction(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (mounted && _active) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is FormatException ? e.message : '操作未完成，请重新核对后重试'),
          ),
        );
      }
    }
  }

  Future<bool> _confirm(String title, String text, String button) async {
    Route<dynamic>? dialog;
    return await showDialog<bool>(
              context: context,
              builder: (context) {
                dialog = ModalRoute.of(context);
                if (dialog != null) _dialogs.add(dialog!);
                return AlertDialog(
                  title: Text(title),
                  content: Text(text),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('取消'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(button),
                    ),
                  ],
                );
              },
            ).whenComplete(() => _dialogs.remove(dialog)) ==
            true &&
        _active;
  }

  Future<void> _send() async {
    Route<dynamic>? dialog;
    final value = await widget.request('prepareSend', {}) as Map;
    if (!mounted || !_active) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (context) {
        dialog = ModalRoute.of(context);
        if (dialog != null) _dialogs.add(dialog!);
        return AlertDialog(
          title: const Text('允许发送本轮对话？'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${value['model']} · ${value['host']}'),
                  const SizedBox(height: 12),
                  const Text('将发送以下本轮内容和已有对话历史。已标记的敏感行以占位符发送。'),
                  SelectableText(value['text'] as String),
                  if ((value['targets'] as List).isNotEmpty) ...[
                    const Text('所选卡片标识用于模型提出草案，仍需本人采用并核对：'),
                    for (final target in value['targets'] as List)
                      SelectableText(
                        '${target['id']}${target['bundle'] == true ? '（组合）' : '（卡片）'}',
                      ),
                  ],
                  if ((value['attachments'] as List).isNotEmpty) ...[
                    const Text('核对以下实际附件范围；敏感行标记仅适用于主输入，附件及转写不会自动替换敏感内容。'),
                    for (final a in value['attachments'] as List) ...[
                      Text(a['sendDescription'] as String? ?? ''),
                      if (a['transcript'] != null)
                        SelectableText(a['transcript'] as String),
                      _attachment(a as Map, false),
                    ],
                  ],
                  const Divider(),
                  const Text('将重发的对话历史'),
                  SelectableText(value['history'] as String),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('允许本次发送'),
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogs.remove(dialog));
    if (!_active) return;
    await widget.act(allowed == true ? 'send' : 'cancelSend', {
      'ticket': value['ticket'],
    });
  }

  Future<void> _preview(Map meta, bool editable) async {
    Future<void> preview() async {
      ConversationAttachment? owned;
      Route<dynamic>? dialog;
      try {
        final value =
            await widget.request('readAttachment', {'id': meta['id']}) as Map;
        try {
          if (!mounted || !_active) return;
          owned = ConversationAttachment.fromJson({
            ...value,
            'bytes': base64Encode(value['bytes'] as Uint8List),
            if (value['normalizedAudio'] != null)
              'normalizedAudio': base64Encode(
                value['normalizedAudio'] as Uint8List,
              ),
            'frames': [
              for (final f in value['frames'] as List)
                {'ms': f['ms'], 'bytes': base64Encode(f['bytes'] as Uint8List)},
            ],
          });
        } finally {
          final audio = value['normalizedAudio'] as Uint8List?;
          audio?.fillRange(0, audio.length, 0);
          final bytes = value['bytes'] as Uint8List;
          bytes.fillRange(0, bytes.length, 0);
          for (final f in value['frames'] as List) {
            final b = f['bytes'] as Uint8List;
            b.fillRange(0, b.length, 0);
          }
        }
        if (!mounted || !_active) return;
        await showAttachmentPreview(
          context,
          attachment: owned,
          session: widget.session,
          speechBinding: editable && !_working ? widget.speechBinding : null,
          onSpeechSettings: widget.openSpeechSettings,
          onAudio: editable && !_working
              ? (wav) => widget.act('attachmentAudio', {
                  'id': meta['id'],
                  'wav': wav,
                })
              : null,
          onTranscript: editable && !_working
              ? (text) => widget.act('attachmentTranscript', {
                  'id': meta['id'],
                  'text': text,
                })
              : null,
          onDialog: (value) {
            _dialogs.remove(dialog);
            dialog = value == null ? null : ModalRoute.of(value);
            if (dialog != null) _dialogs.add(dialog!);
          },
          onFrames: editable && !_working
              ? (frames) async {
                  try {
                    await widget.act('videoFrames', {
                      'id': meta['id'],
                      'frames': [
                        for (final frame in frames)
                          {'ms': frame.milliseconds, 'bytes': frame.bytes},
                      ],
                    });
                  } finally {
                    for (final frame in frames) {
                      frame.bytes.fillRange(0, frame.bytes.length, 0);
                    }
                  }
                }
              : null,
        );
      } finally {
        _dialogs.remove(dialog);
        owned?.wipe();
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
      }
    }

    final pending = preview();
    _reads.add(pending);
    try {
      await pending;
    } finally {
      _reads.remove(pending);
    }
  }

  Widget _attachment(Map a, bool editable) => Card(
    child: ListTile(
      title: Text(a['name'] as String),
      subtitle: Text(
        '${a['size']} 字节 · ${a['kind']}${(a['frames'] as List).isEmpty ? '' : ' · 已选${(a['frames'] as List).length}帧'}',
      ),
      onTap: () => _errorAction(() => _preview(a, editable)),
      trailing: Wrap(
        children: [
          if (a['card'] == null && a['blob'] == null)
            TextButton(
              onPressed: _working
                  ? null
                  : () => widget.act('saveAttachment', {'id': a['id']}),
              child: const Text('另存原件'),
            ),
          if (editable)
            IconButton(
              tooltip: '移除附件',
              icon: const Icon(Icons.close),
              onPressed: _working
                  ? null
                  : () => widget.act('removeAttachment', {'id': a['id']}),
            ),
        ],
      ),
    ),
  );

  Future<void> _choose(bool originals) async {
    final choices = originals
        ? (widget.data['originals'] as List? ?? []).cast<Map>()
        : (widget.data['targets'] as List? ?? []).cast<Map>();
    Route<dynamic>? dialog;
    final id = await showDialog<String>(
      context: context,
      builder: (context) {
        dialog = ModalRoute.of(context);
        if (dialog != null) _dialogs.add(dialog!);
        return AlertDialog(
          title: Text(originals ? '选择原始资料' : '选择卡片'),
          content: SizedBox(
            width: 480,
            height: 360,
            child: ListView(
              children: [
                for (final item in choices)
                  ListTile(
                    title: Text(item[originals ? 'name' : 'title'] as String),
                    onTap: () => Navigator.pop(context, item['id']),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
          ],
        );
      },
    ).whenComplete(() => _dialogs.remove(dialog));
    if (id != null && _active) {
      await widget.act(originals ? 'attachOriginal' : 'attachCard', {'id': id});
    }
  }

  Widget _message(Map raw) {
    final message = ConversationMessage(
      raw['role'] as String,
      raw['text'] as String,
      reviewId: raw['reviewId'] as String,
      accepted: raw['accepted'] == true,
      suggestions: [
        for (final s in raw['suggestions'] as List)
          AiCardSuggestion(
            title: s['title'] as String,
            content: s['content'] as String,
            kind: CardKind.values.byName(s['kind'] as String),
            isInference: s['inference'] == true,
            tags: List<String>.from(s['tags'] as List),
          ),
      ],
      actions: [
        for (final p in raw['actions'] as List)
          ReviewActions.fromJson(p as Map),
      ],
      proposals: [
        for (final p in raw['proposals'] as List)
          p == null ? null : ReviewActionProposal.fromJson(p as Map),
      ],
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              message.role == 'user' ? '我' : 'LiveRelay',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            SelectableText(message.text),
            for (final a in raw['attachments'] as List)
              _attachment(a as Map, false),
            for (var i = 0; i < message.suggestions.length; i++)
              SuggestionReviewEditor(
                key: ValueKey('${message.reviewId}/$i/editor'),
                message: message,
                index: i,
                cards: _targets,
                working: _working,
                onSuggestion: (next) {
                  final previous = message.suggestions[i];
                  widget.act('editSuggestion', {
                    'reviewId': message.reviewId,
                    'index': i,
                    'suggestion': {
                      if (next.title != previous.title) 'title': next.title,
                      if (next.content != previous.content)
                        'content': next.content,
                      if (next.kind != previous.kind) 'kind': next.kind.name,
                      if (next.isInference != previous.isInference)
                        'inference': next.isInference,
                      if (next.tags.join('\u0000') !=
                          previous.tags.join('\u0000'))
                        'tags': next.tags,
                    },
                  });
                },
                onActions: (plan) => widget.act('editActions', {
                  'reviewId': message.reviewId,
                  'index': i,
                  'plan': plan.toJson(),
                }),
                onAdopt: () => widget.act('adoptProposal', {
                  'reviewId': message.reviewId,
                  'index': i,
                }),
              ),
            if (message.suggestions.isNotEmpty) ...[
              const Text('确认时保留完整输入、附件和实际操作计划，可从卡片查看来源。'),
              for (var i = 0; i < message.actions.length; i++)
                Text(
                  '卡片${i + 1}：${reviewPlanSummary(message.actions[i], _targets)}',
                ),
              if (message.accepted)
                const Text('已确认并保存 · 本人选择的操作已执行')
              else
                FilledButton.icon(
                  icon: const Icon(Icons.check),
                  label: Text('确认并保存 ${message.suggestions.length} 张卡片'),
                  onPressed: _working
                      ? null
                      : () => widget.act('accept', {
                          'reviewId': message.reviewId,
                          'stamp': raw['stamp'],
                        }),
                ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data, draft = widget.data['draft'] as String? ?? '';
    final models = (data['models'] as List? ?? []).cast<Map>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            children: [
              if (models.isNotEmpty)
                DropdownButton<String>(
                  value: '${data['profile']}\u0000${data['model']}',
                  items: [
                    for (final model in models)
                      DropdownMenuItem(
                        value: '${model['id']}\u0000${model['model']}',
                        child: Text('${model['name']} · ${model['model']}'),
                      ),
                  ],
                  onChanged: _working
                      ? null
                      : (value) => _errorAction(() async {
                          if (value == null ||
                              value ==
                                  '${data['profile']}\u0000${data['model']}') {
                            return;
                          }
                          final stamp = data['conversationStamp'];
                          if (await _confirm(
                            '切换服务或模型？',
                            '将清空当前会话和输入，已保存卡片保留；历史不会自动发给新服务。',
                            '切换并开始新会话',
                          )) {
                            final parts = value.split('\u0000');
                            await widget.act('selectModel', {
                              'id': parts[0],
                              'model': parts[1],
                              'stamp': stamp,
                            });
                          }
                        }),
                )
              else
                Text('${data['model'] ?? '尚未配置 AI 服务'}'),
              IconButton(
                tooltip: 'AI 服务设置',
                onPressed: _working ? null : widget.openSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
              TextButton(
                onPressed: _working
                    ? null
                    : () => _errorAction(() async {
                        final stamp = data['conversationStamp'];
                        if (await _confirm(
                          '开始新会话？',
                          '清空当前会话和输入；已保存卡片保留。',
                          '开始新会话',
                        )) {
                          await widget.act('newConversation', {'stamp': stamp});
                        }
                      }),
                child: const Text('新会话'),
              ),
              TextButton(
                onPressed: widget.openManual,
                child: const Text('手动新建卡片'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            controller: _messageScroll,
            padding: const EdgeInsets.all(12),
            children: [
              if ((data['messages'] as List? ?? []).isEmpty)
                const Text('可以继续追问、修改建议，再明确确认保存。'),
              for (final message in data['messages'] as List? ?? [])
                _message(message as Map),
            ],
          ),
        ),
        if (data['error'] != null)
          Row(
            children: [
              Expanded(child: Text(data['error'] as String)),
              TextButton(
                onPressed: () => widget.act('flush', {}),
                child: const Text('重试保存'),
              ),
            ],
          ),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropTarget(
                    enable: !_working,
                    onDragEntered: (_) => setState(() => _hover = true),
                    onDragExited: (_) => setState(() => _hover = false),
                    onDragDone: (details) {
                      setState(() => _hover = false);
                      widget.act('addFiles', {
                        'paths': details.files.map((f) => f.path).toList(),
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _hover
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                      child: Column(
                        children: [
                          Wrap(
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.attach_file),
                                label: const Text('添加附件'),
                                onPressed: _working
                                    ? null
                                    : () => _errorAction(() async {
                                        final files =
                                            await FilePicker.pickFiles(
                                              dialogTitle: '选择会话附件',
                                            );
                                        if (_active) {
                                          await widget.act('addFiles', {
                                            'paths': files
                                                .map((f) => f.xFile.path)
                                                .toList(),
                                          });
                                        }
                                      }),
                              ),
                              TextButton(
                                onPressed: _working
                                    ? null
                                    : () => _choose(false),
                                child: const Text('引用卡片'),
                              ),
                              TextButton(
                                onPressed: _working
                                    ? null
                                    : () => _choose(true),
                                child: const Text('引用原件'),
                              ),
                            ],
                          ),
                          const Text('附件加入会话；另存原件需单独选择。可拖入本地文件。'),
                          for (final a in _attachments) _attachment(a, true),
                        ],
                      ),
                    ),
                  ),
                  ReviewTextField(
                    label: '对话输入',
                    value: draft,
                    maxLines: 5,
                    enabled: !_working,
                    onChanged: (text) => widget.act('draft', {'text': text}),
                  ),
                  if (draft.isNotEmpty)
                    ExpansionTile(
                      title: const Text('标记敏感行'),
                      children: [
                        for (var i = 0; i < draft.split('\n').length; i++)
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  '${i + 1}. ${draft.split('\n')[i]}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              DropdownButton<SensitiveFieldKind?>(
                                value: (data['marks'] as Map?)?['$i'] == null
                                    ? null
                                    : SensitiveFieldKind.values.byName(
                                        (data['marks'] as Map)['$i'] as String,
                                      ),
                                items: const [
                                  DropdownMenuItem(
                                    value: null,
                                    child: Text('公开'),
                                  ),
                                  DropdownMenuItem(
                                    value: SensitiveFieldKind.account,
                                    child: Text('账号'),
                                  ),
                                  DropdownMenuItem(
                                    value: SensitiveFieldKind.secret,
                                    child: Text('秘密'),
                                  ),
                                  DropdownMenuItem(
                                    value: SensitiveFieldKind.money,
                                    child: Text('金额'),
                                  ),
                                  DropdownMenuItem(
                                    value: SensitiveFieldKind.note,
                                    child: Text('私密备注'),
                                  ),
                                ],
                                onChanged: _working
                                    ? null
                                    : (kind) => widget.act('mark', {
                                        'line': i,
                                        'kind': kind?.name,
                                      }),
                              ),
                            ],
                          ),
                      ],
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('发送'),
                        onPressed:
                            _working ||
                                (draft.trim().isEmpty && _attachments.isEmpty)
                            ? null
                            : () => _errorAction(_send),
                      ),
                      IconButton(
                        tooltip: '语音输入',
                        onPressed: _working ? null : widget.openSpeech,
                        icon: const Icon(Icons.mic_none),
                      ),
                      if (_working)
                        TextButton(
                          onPressed: () => widget.act('cancelAgent', {}),
                          child: const Text('停止'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
