import 'package:flutter/material.dart';

import '../../application/agent/agent_conversation.dart';
import '../../core/domain/entities.dart';
import '../dialogs/ai_settings_dialog.dart';

class ConversationView extends StatelessWidget {
  const ConversationView({
    super.key,
    required this.conversation,
    required this.openManual,
    required this.openSpeech,
  });
  final AgentConversation conversation;
  final VoidCallback openManual, openSpeech;
  Future<void> _send(BuildContext context) async {
    final c = conversation;
    final generationText = c.draft;
    try {
      final turn = c.prepare(generationText, [
        for (final e in c.marks.entries)
          SensitiveMark(lineOrder: e.key, kind: e.value),
      ]);
      final settings = c.controller.aiSettings;
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('允许发送本轮对话？'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${settings.model} · ${Uri.tryParse(settings.endpoint)?.host ?? "尚未配置"}',
                  ),
                  const SizedBox(height: 12),
                  const Text('将发送以下本轮内容和已有对话历史。已标记的敏感行以占位符发送。'),
                  const SizedBox(height: 12),
                  SelectableText(turn.payload.redactedText),
                  if (c.disclosureHistory.isNotEmpty) ...[
                    const Divider(),
                    const Text('将重发的对话历史'),
                    SelectableText(c.disclosureHistory),
                  ],
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
        ),
      );
      if (allowed == true &&
          c.controller.isUnlocked &&
          c.draft == generationText) {
        await c.send(turn);
      }
    } on Object catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e is FormatException ? e.message : '无法准备对话')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: conversation,
    builder: (context, _) {
      final c = conversation;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  c.controller.aiSettings.isConfigured
                      ? c.controller.aiSettings.model
                      : '尚未配置 AI 服务',
                ),
                IconButton(
                  tooltip: 'AI 服务设置',
                  onPressed: c.working
                      ? null
                      : () => showDialog<void>(
                          context: context,
                          builder: (_) =>
                              AiSettingsDialog(controller: c.controller),
                        ),
                  icon: const Icon(Icons.settings_outlined),
                ),
                TextButton(
                  onPressed: c.working
                      ? null
                      : () async {
                          final allowed = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('开始新会话？'),
                              content: const Text('清空当前会话和输入。已保存的卡片保留。'),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: const Text('取消'),
                                ),
                                FilledButton(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: const Text('开始新会话'),
                                ),
                              ],
                            ),
                          );
                          if (allowed == true) await c.newConversation();
                        },
                  child: const Text('新会话'),
                ),
                TextButton(onPressed: openManual, child: const Text('手动新建卡片')),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (c.messages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('告诉我你想整理什么。你可以继续追问、修改建议，再明确确认保存。'),
                  ),
                for (final m in c.messages)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            m.role == 'user' ? '我' : 'LiveRelay',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 8),
                          SelectableText(m.text),
                          for (var i = 0; i < m.suggestions.length; i++)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Column(
                                children: [
                                  if (m.suggestions[i].isInference)
                                    const Text('包含推断，请核对'),
                                  _SharedField(
                                    key: ValueKey('${m.reviewId}/$i/title'),
                                    label: '建议标题',
                                    value: m.suggestions[i].title,
                                    enabled: !m.accepted && !c.working,
                                    onChanged: (text) =>
                                        c.editSuggestion(m, i, title: text),
                                  ),
                                  const SizedBox(height: 8),
                                  _SharedField(
                                    key: ValueKey('${m.reviewId}/$i/content'),
                                    label: '建议总结',
                                    value: m.suggestions[i].content,
                                    maxLines: 6,
                                    enabled: !m.accepted && !c.working,
                                    onChanged: (text) =>
                                        c.editSuggestion(m, i, content: text),
                                  ),
                                ],
                              ),
                            ),
                          if (m.suggestions.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            if (m.accepted)
                              const Text('已确认并保存 · 交付可见性保持隐藏')
                            else
                              FilledButton.icon(
                                onPressed: c.working ? null : () => c.accept(m),
                                icon: const Icon(Icons.check),
                                label: Text(
                                  '确认并保存 ${m.suggestions.length} 张卡片',
                                ),
                              ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (c.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Expanded(child: Text(c.error!)),
                  TextButton(onPressed: c.retrySave, child: const Text('重试保存')),
                ],
              ),
            ),
          Flexible(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _SharedField(
                      label: '对话输入',
                      value: c.draft,
                      maxLines: 5,
                      enabled: !c.working,
                      onChanged: c.updateDraft,
                    ),
                    if (c.draft.isNotEmpty)
                      ExpansionTile(
                        title: const Text('标记敏感行'),
                        children: [
                          for (var i = 0; i < c.draft.split('\n').length; i++)
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${i + 1}. ${c.draft.split('\n')[i]}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                DropdownButton<SensitiveFieldKind?>(
                                  value: c.marks[i],
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
                                  onChanged: c.working
                                      ? null
                                      : (value) => c.mark(i, value),
                                ),
                              ],
                            ),
                        ],
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: c.working || c.draft.trim().isEmpty
                              ? null
                              : () => _send(context),
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('发送'),
                        ),
                        IconButton(
                          tooltip: '语音输入',
                          onPressed: c.working ? null : openSpeech,
                          icon: const Icon(Icons.mic_none),
                        ),
                        if (c.working)
                          TextButton(
                            onPressed: c.controller.cancelAgentTask,
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
    },
  );
}

class _SharedField extends StatefulWidget {
  const _SharedField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.maxLines = 1,
    this.enabled = true,
  });
  final String label, value;
  final ValueChanged<String> onChanged;
  final int maxLines;
  final bool enabled;
  @override
  State<_SharedField> createState() => _SharedFieldState();
}

class _SharedFieldState extends State<_SharedField> {
  late final _text = TextEditingController(text: widget.value);
  @override
  void didUpdateWidget(_SharedField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_text.text != widget.value) {
      _text.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(
          offset: _text.selection.baseOffset.clamp(0, widget.value.length),
        ),
      );
    }
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextField(
    controller: _text,
    enabled: widget.enabled,
    minLines: 1,
    maxLines: widget.maxLines,
    decoration: InputDecoration(labelText: widget.label),
    onChanged: widget.onChanged,
  );
}
