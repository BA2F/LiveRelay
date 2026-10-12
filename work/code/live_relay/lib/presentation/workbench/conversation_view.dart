import 'package:flutter/material.dart';

import '../controllers/agent_conversation.dart';
import '../../core/ai/outbound_consent.dart';
import '../../core/domain/entities.dart';
import '../dialogs/ai_settings_dialog.dart';
import '../dialogs/outbound_consent_dialog.dart';
import 'attachment_strip.dart';
import 'review_actions_editor.dart';
import 'suggestion_review_editor.dart';

class ConversationView extends StatelessWidget {
  const ConversationView({
    super.key,
    required this.conversation,
    required this.openManual,
    required this.openSpeech,
  });
  final AgentConversation conversation;
  final VoidCallback openManual, openSpeech;
  Future<void> _selectModel(
    BuildContext context,
    String id,
    String model,
  ) async {
    final c = conversation;
    if (id == c.controller.aiSettings.id &&
        model == c.controller.aiSettings.model) {
      return;
    }
    if (c.messages.isNotEmpty ||
        c.draft.isNotEmpty ||
        c.attachments.isNotEmpty) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('切换服务或模型？'),
          content: const Text('切换会清空当前会话和输入，已保存的卡片保留。已有历史不会自动发给新服务。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('切换并开始新会话'),
            ),
          ],
        ),
      );
      if (allowed != true || !context.mounted) return;
    }
    try {
      await c.controller.selectAiProfile(id, model);
      await c.newConversation();
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(c.controller.lastError ?? '切换失败，当前会话已保留')),
        );
      }
    }
  }

  /// 日常发送：内容常驻在输入区上方，所见即所发；只有首次向该服务
  /// 发送内容、首次发送附件时各拦一次。
  Future<void> send(BuildContext context) async {
    final c = conversation;
    final generationText = c.draft;
    try {
      final turn = c.prepare(generationText, [
        for (final e in c.marks.entries)
          SensitiveMark(lineOrder: e.key, kind: e.value),
      ]);
      final destination = outboundDestination(c);
      if (!await ensureOutboundConsent(
        context,
        c.controller,
        destination: destination,
        kind: OutboundKind.content,
      )) {
        return;
      }
      if (turn.attachments.isNotEmpty) {
        if (!context.mounted) return;
        if (!await ensureOutboundConsent(
          context,
          c.controller,
          destination: destination,
          kind: OutboundKind.attachment,
          attachmentLines: [
            for (final a in turn.attachments) '${a.name} · ${a.sendDescription}',
          ],
        )) {
          return;
        }
      }
      if (context.mounted &&
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

  static OutboundDestination outboundDestination(AgentConversation c) {
    final settings = c.controller.aiSettings;
    return OutboundDestination.ai(
      profileId: settings.id,
      endpoint: settings.endpoint,
      name: settings.name,
    );
  }

  ({PreparedConversationTurn? turn, String? error}) _preview(
    AgentConversation c,
  ) {
    if (c.draft.trim().isEmpty && c.attachments.isEmpty) {
      return (turn: null, error: null);
    }
    try {
      return (
        turn: c.prepare(c.draft, [
          for (final e in c.marks.entries)
            SensitiveMark(lineOrder: e.key, kind: e.value),
        ]),
        error: null,
      );
    } on Object catch (e) {
      return (turn: null, error: e is FormatException ? e.message : '无法准备对话');
    }
  }

  Widget _previewPanel(BuildContext context, AgentConversation c) {
    if (c.draft.trim().isEmpty && c.attachments.isEmpty) {
      return const SizedBox.shrink();
    }
    final preview = _preview(c);
    final settings = c.controller.aiSettings;
    final service = Uri.tryParse(settings.endpoint)?.host ?? '尚未配置';
    final granted = c.controller.outboundConsent.granted(
      outboundDestination(c),
      OutboundKind.content,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: OutboundPreviewPanel(
        service: '${settings.model} · $service',
        children: [
          if (preview.error != null)
            Text(
              preview.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            )
          else if (preview.turn != null) ...[
            const Text('对话内容（已标记敏感行以占位符发送）'),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 160),
              child: SingleChildScrollView(
                child: SelectableText(preview.turn!.payload.redactedText),
              ),
            ),
            if (preview.turn!.reviewTargets.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('随本轮发送所选卡片标识，供模型提出收纳/引用草案：'),
              for (final target in preview.turn!.reviewTargets)
                SelectableText(
                  '${target.id}${target.bundle ? "（组合）" : "（卡片）"}',
                ),
            ],
            if (preview.turn!.attachments.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('附件按原始内容发送，不做敏感内容替换：'),
              for (final a in preview.turn!.attachments) ...[
                Text('${a.name} · ${a.sendDescription}'),
                if (a.transcript != null) SelectableText(a.transcript!),
              ],
              Wrap(
                children: [
                  for (final a in preview.turn!.attachments)
                    AttachmentTile(attachment: a, conversation: c),
                ],
              ),
            ],
            if (c.disclosureHistory.isNotEmpty)
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('将重发的对话历史'),
                children: [SelectableText(c.disclosureHistory)],
              ),
            if (!granted)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('首次向这个服务发送会先确认一次；之后按本面板的范围直接发送。'),
              ),
          ],
        ],
      ),
    );
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
                if (c.controller.aiProfiles.isNotEmpty)
                  DropdownButton<({String id, String model})>(
                    key: const ValueKey('conversation-model'),
                    value: (
                      id: c.controller.aiSettings.id,
                      model: c.controller.aiSettings.model,
                    ),
                    items: [
                      for (final p in c.controller.aiProfiles)
                        for (final model in p.models)
                          DropdownMenuItem(
                            value: (id: p.id, model: model),
                            child: Text('${p.name} · $model'),
                          ),
                    ],
                    onChanged: c.working
                        ? null
                        : (v) {
                            if (v != null) _selectModel(context, v.id, v.model);
                          },
                  )
                else
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
                          if (m.attachments.isNotEmpty)
                            Wrap(
                              children: [
                                for (final a in m.attachments)
                                  AttachmentTile(
                                    attachment: a,
                                    conversation: c,
                                  ),
                              ],
                            ),
                          for (var i = 0; i < m.suggestions.length; i++)
                            SuggestionReviewEditor(
                              key: ValueKey('${m.reviewId}/$i/editor'),
                              message: m,
                              index: i,
                              cards: c.controller.cards,
                              working: c.working,
                              onSuggestion: (value) => c.editSuggestion(
                                m,
                                i,
                                title: value.title,
                                content: value.content,
                                kind: value.kind,
                                isInference: value.isInference,
                                tags: value.tags,
                              ),
                              onActions: (value) => c.editActions(m, i, value),
                              onAdopt: () => c.adoptProposal(m, i),
                            ),
                          if (m.suggestions.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            const Text('确认时会保留此前完整输入和附件，之后可从卡片查看来源。'),
                            for (var i = 0; i < m.actions.length; i++)
                              Text(
                                '卡片${i + 1}：${reviewPlanSummary(m.actions[i], c.controller.cards)}',
                              ),
                            if (m.accepted)
                              const Text('已确认并保存 · 本人选择的操作已执行')
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 输入、标记与“将发送”面板可以滚动；发送行始终留在窗口内。
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AttachmentStrip(conversation: c),
                          const SizedBox(height: 8),
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
                                for (
                                  var i = 0;
                                  i < c.draft.split('\n').length;
                                  i++
                                )
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
                          _previewPanel(context, c),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed:
                            c.working ||
                                (c.draft.trim().isEmpty &&
                                    c.attachments.isEmpty)
                            ? null
                            : () => send(context),
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
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class _SharedField extends StatefulWidget {
  const _SharedField({
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
