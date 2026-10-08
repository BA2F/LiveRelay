import 'dart:io';
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/agent_conversation.dart';
import '../contracts/preview_session.dart';
import '../controllers/speech_input_binding.dart';
import '../../infrastructure/local_media_processor.dart';
import '../pages/speech_input_page.dart';
import '../../core/ai/conversation_attachment.dart';
import '../widgets/local_media_preview.dart';
import '../widgets/local_pdf_preview.dart';

class AttachmentStrip extends StatefulWidget {
  const AttachmentStrip({super.key, required this.conversation});
  final AgentConversation conversation;
  @override
  State<AttachmentStrip> createState() => _AttachmentStripState();
}

class _AttachmentStripState extends State<AttachmentStrip> {
  bool _hover = false;
  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
    } on Object catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FormatException ? e.message : '附件读取失败')),
        );
      }
    }
  }

  Future<void> _choose(bool originals) async {
    final c = widget.conversation;
    final choices = originals
        ? c.controller.blobs
              .where((b) => !c.controller.recycledBlobIds.contains(b.id))
              .map((b) => (b.id, b.originalName))
              .toList()
        : c.controller.cards.map((b) => (b.id, b.title)).toList();
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(originals ? '选择原始资料' : '选择卡片'),
        content: SizedBox(
          width: 480,
          height: 360,
          child: choices.isEmpty
              ? const Center(child: Text('暂无资料'))
              : ListView(
                  children: [
                    for (final item in choices)
                      ListTile(
                        title: Text(item.$2),
                        onTap: () => Navigator.pop(context, item.$1),
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
      ),
    );
    if (selected == null || !mounted || !c.controller.isUnlocked) return;
    await _action(() async {
      if (originals) {
        await c.attachOriginal(
          c.controller.blobs.firstWhere((b) => b.id == selected),
        );
      } else {
        c.attachCard(c.controller.cards.firstWhere((b) => b.id == selected));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    return DropTarget(
      enable: !c.working,
      onDragEntered: (_) => setState(() => _hover = true),
      onDragExited: (_) => setState(() => _hover = false),
      onDragDone: (details) {
        setState(() => _hover = false);
        _action(() => c.addFilePaths(details.files.map((f) => f.path)));
      },
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          border: Border.all(
            color: _hover
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  onPressed: c.working
                      ? null
                      : () => _action(() async {
                          final files = await FilePicker.pickFiles(
                            dialogTitle: '选择会话附件',
                          );
                          if (mounted) {
                            await c.addFilePaths(
                              files.map((f) => f.xFile.path),
                            );
                          }
                        }),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('添加附件'),
                ),
                TextButton(
                  onPressed: c.working ? null : () => _choose(false),
                  child: const Text('引用卡片'),
                ),
                TextButton(
                  onPressed: c.working ? null : () => _choose(true),
                  child: const Text('引用原件'),
                ),
              ],
            ),
            if (c.attachments.isEmpty)
              const Text(
                '可将本地文件拖到这里。附件只加入会话；另存原件需单独选择。',
                style: TextStyle(fontSize: 12),
              ),
            if (c.attachments.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final a in c.attachments)
                    AttachmentTile(
                      attachment: a,
                      conversation: c,
                      removable: true,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({
    super.key,
    required this.attachment,
    required this.conversation,
    this.removable = false,
  });
  final ConversationAttachment attachment;
  final AgentConversation conversation;
  final bool removable;
  Future<void> _preview(BuildContext context) async {
    await showAttachmentPreview(
      context,
      attachment: attachment,
      session: conversation.controller,
      speechBinding: removable
          ? LocalSpeechInputBinding(conversation.controller)
          : null,
      onAudio: removable && !conversation.working
          ? (wav) async => conversation.setAttachmentAudio(
              attachment,
              wav == null ? null : Uint8List.fromList(wav),
            )
          : null,
      onTranscript: removable && !conversation.working
          ? (text) async =>
                conversation.setAttachmentTranscript(attachment, text)
          : null,
      onFrames: removable && !conversation.working
          ? (frames) async =>
                conversation.replaceVideoFrames(attachment, frames)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final a = attachment;
    return SizedBox(
      width: 180,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      a.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (removable)
                    IconButton(
                      tooltip: '移除附件',
                      onPressed: conversation.working
                          ? null
                          : () => conversation.removeAttachment(a),
                      icon: const Icon(Icons.close),
                      visualDensity: VisualDensity.compact,
                    ),
                ],
              ),
              Text(a.sendDescription, style: const TextStyle(fontSize: 11)),
              InkWell(
                key: ValueKey('attachment-preview-${a.id}'),
                onTap: () => _preview(context),
                child: a.kind == ConversationAttachmentKind.image
                    ? Image.memory(
                        a.bytes,
                        height: 56,
                        cacheWidth: 160,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      )
                    : const Icon(Icons.description_outlined),
              ),
              Text(
                '${(a.bytes.length / 1024).toStringAsFixed(1)} KB',
                style: Theme.of(context).textTheme.labelSmall,
              ),
              if (a.frames.isNotEmpty)
                Wrap(
                  children: [
                    for (final frame in a.frames)
                      Column(
                        children: [
                          Image.memory(frame.bytes, width: 72, height: 42),
                          Text(
                            '${(frame.milliseconds / 1000).toStringAsFixed(1)} s',
                          ),
                        ],
                      ),
                  ],
                ),
              if (a.kind == ConversationAttachmentKind.unsupported)
                const Text('当前协议不支持发送', style: TextStyle(fontSize: 11)),
              if (a.blobId != null || a.cardId != null)
                const Text('已在资料库', style: TextStyle(fontSize: 11))
              else
                TextButton(
                  onPressed: conversation.working
                      ? null
                      : () async {
                          try {
                            await conversation.saveOriginal(a);
                          } on Object {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('保存原件失败，可重试')),
                              );
                            }
                          }
                        },
                  child: const Text('另存原件'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> showAttachmentPreview(
  BuildContext context, {
  required ConversationAttachment attachment,
  required PreviewSession session,
  ValueChanged<BuildContext?>? onDialog,
  SpeechInputBinding? speechBinding,
  VoidCallback? onSpeechSettings,
  Future<void> Function(Uint8List? wav)? onAudio,
  Future<void> Function(String? text)? onTranscript,
  Future<void> Function(List<({int milliseconds, Uint8List bytes})> frames)?
  onFrames,
}) async {
  final a = attachment;
  final key = GlobalKey<LocalMediaPreviewState>();
  var busy = false;
  BuildContext? dialogContext;
  BuildContext? speechDialogContext;
  final processor = LocalMediaProcessor(
    session,
    active: () => dialogContext?.mounted == true,
  );
  final pending = <Future<void>>{};
  Future<void> action(
    BuildContext context,
    StateSetter update,
    Future<void> Function() work,
  ) async {
    update(() => busy = true);
    final operation = (() async {
      try {
        await work();
      } on Object catch (e) {
        if (context.mounted && session.isUnlocked) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(e is FormatException ? e.message : '媒体处理失败'),
            ),
          );
        }
      } finally {
        if (context.mounted && session.isUnlocked) update(() => busy = false);
      }
    })();
    pending.add(operation);
    try {
      await operation;
    } finally {
      pending.remove(operation);
    }
  }

  final media = {
    ConversationAttachmentKind.audio,
    ConversationAttachmentKind.video,
  }.contains(a.kind);
  Future<void> dismiss() async {
    final speechDialog = speechDialogContext;
    speechDialogContext = null;
    if (speechDialog != null && speechDialog.mounted) {
      final route = ModalRoute.of(speechDialog);
      if (route != null && route.isActive) {
        Navigator.of(speechDialog).removeRoute(route);
      }
    }
    final current = dialogContext;
    if (current != null && current.mounted) {
      final route = ModalRoute.of(current);
      if (route != null && route.isActive) {
        Navigator.of(current).removeRoute(route);
      }
    }
    await processor.close();
    await Future.wait(List.of(pending));
  }

  session.registerPreviewCleanup(dismiss);
  try {
    await showDialog<void>(
      context: context,
      builder: (context) {
        dialogContext = context;
        onDialog?.call(context);
        return StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(a.name),
            content: SizedBox(
              width: 640,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Platform.isLinux &&
                            {
                              ConversationAttachmentKind.audio,
                              ConversationAttachmentKind.video,
                            }.contains(a.kind)
                        ? LocalMediaPreview(
                            key: key,
                            controller: session,
                            name: a.name,
                            video: a.kind == ConversationAttachmentKind.video,
                            compact: true,
                            readBytes: () async => Uint8List.fromList(a.bytes),
                          )
                        : Platform.isLinux &&
                              a.kind == ConversationAttachmentKind.pdf
                        ? LocalPdfPreview(
                            session: session,
                            name: a.name,
                            compact: true,
                            readBytes: () async => Uint8List.fromList(a.bytes),
                          )
                        : a.kind == ConversationAttachmentKind.image
                        ? Image.memory(
                            a.bytes,
                            cacheWidth: 1024,
                            errorBuilder: (_, _, _) => const Text('无法显示图片'),
                          )
                        : SelectableText(
                            a.kind == ConversationAttachmentKind.text
                                ? a.text
                                : '${a.mimeType} · ${a.bytes.length} 字节',
                          ),
                    if (a.kind == ConversationAttachmentKind.video)
                      Text(
                        '发送已检查采样帧和时间。${a.transcript != null
                            ? "音轨只发送核对转写。"
                            : a.normalizedAudio != null
                            ? "另发送完整转换音轨。"
                            : "尚未选择音轨。"}',
                      ),
                    if (media)
                      Text(
                        a.transcript != null
                            ? '本轮音频：仅发送本人核对文字\n${a.transcript}'
                            : a.normalizedAudio != null
                            ? '本轮音频：完整16 kHz WAV（${a.normalizedAudio!.length}字节）；需要Chat音频模型。'
                            : '音频需要Chat音频模型；Responses可使用核对转写。',
                      ),
                    if (a.frames.isNotEmpty)
                      Wrap(
                        children: [
                          for (final frame in a.frames)
                            Column(
                              children: [
                                Image.memory(
                                  frame.bytes,
                                  width: 120,
                                  height: 80,
                                ),
                                Text(
                                  '${(frame.milliseconds / 1000).toStringAsFixed(1)} s',
                                ),
                              ],
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              if (media && onAudio != null && Platform.isLinux)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(context, update, () async {
                          final wav = await processor.normalizeAudio(a.bytes);
                          try {
                            if (!session.isUnlocked || !context.mounted) return;
                            await onAudio(wav);
                            if (context.mounted) Navigator.pop(context);
                          } finally {
                            wav.fillRange(0, wav.length, 0);
                          }
                        }),
                  child: const Text('准备完整WAV音轨'),
                ),
              if (media && speechBinding != null && onTranscript != null)
                OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => action(context, update, () async {
                          String? adopted;
                          await showDialog<void>(
                            context: context,
                            builder: (dialog) {
                              speechDialogContext = dialog;
                              return Dialog(
                                child: SizedBox(
                                  width: 680,
                                  height: 620,
                                  child: SpeechInputPage(
                                    binding: speechBinding,
                                    onSettings: onSpeechSettings,
                                    readAudio: () async =>
                                        Uint8List.fromList(a.bytes),
                                    audioName: a.name,
                                    transcriptActionLabel: '使用核对文字发送此附件',
                                    onTranscript: (text) {
                                      adopted = text;
                                      Navigator.pop(dialog);
                                    },
                                  ),
                                ),
                              );
                            },
                          );
                          speechDialogContext = null;
                          if (adopted != null &&
                              session.isUnlocked &&
                              context.mounted) {
                            await onTranscript(adopted);
                            if (context.mounted) Navigator.pop(context);
                          }
                        }),
                  child: const Text('转写并核对音轨'),
                ),
              if (media && a.transcript != null && onTranscript != null)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => action(context, update, () async {
                          await onTranscript(null);
                          if (context.mounted) Navigator.pop(context);
                        }),
                  child: const Text('恢复音频输入'),
                ),

              if (a.kind == ConversationAttachmentKind.video &&
                  onFrames != null &&
                  Platform.isLinux)
                FilledButton(
                  onPressed: busy || !session.isUnlocked
                      ? null
                      : () async {
                          update(() => busy = true);
                          try {
                            final frames = await key.currentState!
                                .sampleFrames();
                            await onFrames(frames);
                            if (context.mounted) Navigator.pop(context);
                          } on Object catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    e is FormatException
                                        ? e.message
                                        : '无法选取视频帧',
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) update(() => busy = false);
                          }
                        },
                  child: Text(busy ? '正在选帧…' : '选取4帧供发送前检查'),
                ),
              TextButton(
                onPressed: busy ? null : () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        );
      },
    );
  } finally {
    await processor.close();
    await Future.wait(List.of(pending));
    onDialog?.call(null);
    session.unregisterPreviewCleanup(dismiss);
  }
}
