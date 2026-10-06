import 'package:flutter/material.dart';

import '../../application/agent/agent_conversation.dart';
import '../../core/ai/review_actions.dart';
import '../../core/domain/entities.dart';
import '../model_labels.dart';

String reviewLevelLabel(VisibilityLevel level) => switch (level) {
  VisibilityLevel.summary => '正文前80字',
  VisibilityLevel.original => '完整正文，原件另行选择',
  _ => level.label,
};

String reviewPlanSummary(ReviewActions plan, List<LifeCard> cards) {
  String title(String id) =>
      cards.where((c) => c.id == id).firstOrNull?.title ?? '目标已失效';
  return [
    plan.bundleId == null ? '独立保存' : '收纳：${title(plan.bundleId!)}',
    '引用：${plan.referenceIds.isEmpty ? "无" : plan.referenceIds.map(title).join("、")}',
    '失能：${reviewLevelLabel(plan.incapacitated)}',
    '身故：${reviewLevelLabel(plan.deceased)}',
  ].join(' · ');
}

class ReviewActionsEditor extends StatefulWidget {
  const ReviewActionsEditor({
    super.key,
    required this.conversation,
    required this.message,
    required this.index,
  });
  final AgentConversation conversation;
  final ConversationMessage message;
  final int index;
  @override
  State<ReviewActionsEditor> createState() => _ReviewActionsEditorState();
}

class _ReviewActionsEditorState extends State<ReviewActionsEditor> {
  String _query = '';
  ReviewActions get _plan => widget.message.actions[widget.index];
  bool get _enabled => !widget.message.accepted && !widget.conversation.working;
  void _change({
    String? bundleId,
    bool changeBundle = false,
    List<String>? references,
    VisibilityLevel? incapacitated,
    VisibilityLevel? deceased,
  }) {
    widget.conversation.editActions(
      widget.message,
      widget.index,
      ReviewActions(
        bundleId: changeBundle ? bundleId : _plan.bundleId,
        referenceIds: references ?? _plan.referenceIds,
        incapacitated: incapacitated ?? _plan.incapacitated,
        deceased: deceased ?? _plan.deceased,
      ),
    );
  }

  Widget _visibility(bool deceased) {
    final value = deceased ? _plan.deceased : _plan.incapacitated;
    return DropdownButtonFormField<VisibilityLevel>(
      key: ValueKey(
        '${widget.message.reviewId}/${widget.index}/${deceased ? 'deceased' : 'incapacitated'}/${value.name}',
      ),
      initialValue: value,
      decoration: InputDecoration(
        labelText: deceased ? '身故时可见层级' : '临时失能时可见层级',
      ),
      isExpanded: true,
      items: [
        for (final level in ReviewActions.cardLevels)
          DropdownMenuItem(value: level, child: Text(reviewLevelLabel(level))),
      ],
      onChanged: !_enabled
          ? null
          : (level) {
              if (level == null) return;
              _change(
                deceased: deceased ? level : null,
                incapacitated: deceased ? null : level,
              );
            },
    );
  }

  @override
  Widget build(BuildContext context) {
    final cards = widget.conversation.controller.cards;
    final bundles = cards.where((c) => c.kind == CardKind.bundle).toList();
    final selected = bundles.where((c) => c.id == _plan.bundleId).firstOrNull;
    final matches = cards
        .where(
          (c) => '${c.title}\n${c.content}'.toLowerCase().contains(
            _query.toLowerCase(),
          ),
        )
        .toList();
    final proposal = widget.message.proposals[widget.index];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (proposal != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.message.accepted
                        ? '模型操作草案（实际操作见确认计划）'
                        : '模型操作草案（尚未授权执行）',
                  ),
                  Text(reviewPlanSummary(proposal.plan, cards)),
                  if (proposal.reason.isNotEmpty)
                    SelectableText(proposal.reason),
                  if (!widget.message.accepted)
                    TextButton(
                      key: ValueKey(
                        'adopt-proposal-${widget.message.reviewId}-${widget.index}',
                      ),
                      onPressed: !_enabled
                          ? null
                          : () => widget.conversation.adoptProposal(
                              widget.message,
                              widget.index,
                            ),
                      child: const Text('采用此草案，继续核对保存计划'),
                    ),
                ],
              ),
            ),
          ),
        ExpansionTile(
          key: ValueKey(
            'review-actions-${widget.message.reviewId}-${widget.index}',
          ),
          title: const Text('保存时的操作'),
          subtitle: Text(
            '${_plan.bundleId == null ? '独立卡片' : '收纳：${selected?.title ?? "已失效组合"}'} · ${_plan.referenceIds.length}项引用\n失能：${reviewLevelLabel(_plan.incapacitated)} · 身故：${reviewLevelLabel(_plan.deceased)}',
          ),
          childrenPadding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Text(
              '确认后一次保存卡片和以下本人选择的操作。可见层级用于本机规则，实际交接仍需选择接收者和范围；收纳和引用不会继承其他卡片权限。',
            ),
            DropdownButtonFormField<String>(
              key: ValueKey(
                'bundle-${widget.message.reviewId}-${widget.index}-${_plan.bundleId}',
              ),
              initialValue: _plan.bundleId ?? '',
              decoration: const InputDecoration(labelText: '收纳到已有组合'),
              isExpanded: true,
              items: [
                const DropdownMenuItem(value: '', child: Text('保持独立卡片')),
                for (final card in bundles)
                  DropdownMenuItem(value: card.id, child: Text(card.title)),
                if (_plan.bundleId != null && selected == null)
                  DropdownMenuItem(
                    value: _plan.bundleId,
                    child: const Text('组合已失效，请重新选择'),
                  ),
              ],
              onChanged: !_enabled
                  ? null
                  : (id) => _change(
                      bundleId: id == '' ? null : id,
                      changeBundle: true,
                    ),
            ),
            const SizedBox(height: 8),
            _visibility(false),
            const SizedBox(height: 8),
            _visibility(true),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(labelText: '搜索引用目标'),
              onChanged: (value) => setState(() => _query = value),
            ),
            for (final id in _plan.referenceIds.where(
              (id) => !cards.any((c) => c.id == id),
            ))
              ListTile(
                title: const Text('引用已失效，请移除后确认'),
                trailing: IconButton(
                  onPressed: !_enabled
                      ? null
                      : () => _change(
                          references: _plan.referenceIds
                              .where((r) => r != id)
                              .toList(),
                        ),
                  icon: const Icon(Icons.close),
                ),
              ),
            SizedBox(
              height: 180,
              child: ListView.builder(
                itemCount: matches.length,
                itemBuilder: (context, index) {
                  final card = matches[index];
                  return CheckboxListTile(
                    title: Text(card.title),
                    value: _plan.referenceIds.contains(card.id),
                    onChanged: !_enabled
                        ? null
                        : (value) {
                            final next = _plan.referenceIds.toSet();
                            if (value == true) {
                              next.add(card.id);
                            } else {
                              next.remove(card.id);
                            }
                            if (next.length > 200) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('最多选择200项引用')),
                              );
                              return;
                            }
                            _change(references: next.toList());
                          },
                  );
                },
              ),
            ),
          ],
        ),
      ],
    );
  }
}
