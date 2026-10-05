import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../application/agent/agent_conversation.dart';
import '../../core/ai/conversation_attachment.dart';

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
              InkWell(
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(a.name),
                    content: SizedBox(
                      width: 520,
                      child: SingleChildScrollView(
                        child: a.kind == ConversationAttachmentKind.image
                            ? Image.memory(
                                a.bytes,
                                cacheWidth: 1024,
                                errorBuilder: (_, _, _) => const Text('无法显示图片'),
                              )
                            : SelectableText(
                                a.kind == ConversationAttachmentKind.text
                                    ? a.text
                                    : '${a.mimeType} · ${a.bytes.length} 字节\n此文件预览仅展示元信息',
                              ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('关闭'),
                      ),
                    ],
                  ),
                ),
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
