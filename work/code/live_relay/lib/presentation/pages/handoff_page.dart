import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../application/release_preview.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../model_labels.dart';
import '../widgets/release_preview_panel.dart';
import 'manual_handoff_page.dart';

ReleasePolicy _policy(AppController c, String type, String id) =>
    c.releasePolicies
        .where((p) => p.recordType == type && p.recordId == id)
        .firstOrNull ??
    ReleasePolicy(recordType: type, recordId: id);
bool _authorized(ReleasePolicy p) =>
    p.incapacitated != VisibilityLevel.hidden ||
    p.deceased != VisibilityLevel.hidden;

class HandoffPage extends StatelessWidget {
  const HandoffPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    final total = c.cards.length + c.credentials.length;
    final authorized =
        c.cards.where((v) => _authorized(_policy(c, 'card', v.id))).length +
        c.credentials
            .where((v) => _authorized(_policy(c, 'credential', v.id)))
            .length;
    Widget tile(String type, String id, String title) {
      final p = _policy(c, type, id);
      return ListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text('临时失能：${p.incapacitated.label}\n身故：${p.deceased.label}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: c.isBusy
            ? null
            : () => showReleasePolicyDialog(
                context,
                c,
                recordType: type,
                recordId: id,
                recordTitle: title,
              ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (c.handoff != null)
          ListTile(
            leading: const Icon(Icons.send_outlined),
            title: const Text('真实限定范围交接'),
            subtitle: const Text('核对接收者身份，本人明确选择本次交付内容'),
            trailing: const Icon(Icons.chevron_right),
            onTap: c.isBusy
                ? null
                : () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ManualHandoffPage(),
                    ),
                  ),
          ),
        const Text('仅本机模拟 · 预览对象为演示执行人，不会发送给他人，也不自动判断生命状态。'),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '已设置授权 $authorized 条',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text('保持私密 ${total - authorized} 条 · 回收区不参与预览'),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('预览对方能看到什么'),
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const RecipientPreviewPage(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text('已授权的内容', style: Theme.of(context).textTheme.titleLarge),
        if (authorized == 0) const Text('尚未授权。打开一条信息，选择情境并核对精确输出。'),
        for (final card in c.cards.where(
          (v) => _authorized(_policy(c, 'card', v.id)),
        ))
          tile('card', card.id, card.title),
        for (final entry in c.credentials.where(
          (v) => _authorized(_policy(c, 'credential', v.id)),
        ))
          tile('credential', entry.id, entry.title),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text('保持私密的内容 · ${total - authorized} 条'),
          children: [
            for (final card in c.cards.where(
              (v) => !_authorized(_policy(c, 'card', v.id)),
            ))
              tile('card', card.id, card.title),
            for (final entry in c.credentials.where(
              (v) => !_authorized(_policy(c, 'credential', v.id)),
            ))
              tile('credential', entry.id, entry.title),
          ],
        ),
        const Divider(),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.science_outlined),
          title: const Text('打开独立模拟演示'),
          subtitle: Text('仅本机模拟 · 当前状态：${c.lifeState.label}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const SimulationPage()),
          ),
        ),
      ],
    );
  }
}

class RecipientPreviewPage extends StatefulWidget {
  const RecipientPreviewPage({super.key});
  @override
  State<RecipientPreviewPage> createState() => _RecipientPreviewPageState();
}

class _RecipientPreviewPageState extends State<RecipientPreviewPage> {
  LifeState _scene = LifeState.incapacitated;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('接收者预览')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('仅本机模拟 · 演示执行人。切换情境只用于核对，不改变本机模拟状态。'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scene in LifeState.values)
                ChoiceChip(
                  label: Text(scene.label),
                  selected: _scene == scene,
                  onSelected: (_) => setState(() => _scene = scene),
                ),
            ],
          ),
          const SizedBox(height: 16),
          _ReleasedContents(controller: c, scene: _scene),
        ],
      ),
    );
  }
}

class SimulationPage extends StatelessWidget {
  const SimulationPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('仅本机模拟 · 演示')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('这里不进行真实失能或身故核验，不授予银行、继承等处置权。模拟不会通知或发送给他人。'),
          const SizedBox(height: 16),
          Text(
            '当前模拟状态：${c.lifeState.label}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _TransitionActions(controller: c),
          const SizedBox(height: 20),
          _ReleasedContents(controller: c, scene: c.lifeState),
          const SizedBox(height: 20),
          Text('模拟状态历史', style: Theme.of(context).textTheme.titleLarge),
          for (final event in c.lifeStateHistory)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${event.from.label} → ${event.to.label}'),
              subtitle: Text(
                '${event.reason} · ${DateFormat('yyyy-MM-dd HH:mm').format(event.occurredAt.toLocal())}',
              ),
            ),
        ],
      ),
    );
  }
}

class _ReleasedContents extends StatelessWidget {
  const _ReleasedContents({required this.controller, required this.scene});
  final AppController controller;
  final LifeState scene;
  @override
  Widget build(BuildContext context) {
    final cards = controller.cards
        .where(
          (v) =>
              _policy(controller, 'card', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    final credentials = controller.credentials
        .where(
          (v) =>
              _policy(controller, 'credential', v.id).visibleAt(scene) !=
              VisibilityLevel.hidden,
        )
        .toList();
    if (cards.isEmpty && credentials.isEmpty) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        title: '此情境下没有被授权的信息',
        message: '新内容默认保持私密；健康状态不向演示执行人释放信息。',
      );
    }
    return Column(
      children: [
        for (final card in cards) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.card(
              card,
              _policy(controller, 'card', card.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
        for (final entry in credentials) ...[
          ReleasePreviewPanel(
            preview: ReleasePreview.credential(
              entry,
              _policy(controller, 'credential', entry.id).visibleAt(scene),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }
}

class _TransitionActions extends StatelessWidget {
  const _TransitionActions({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final actions = switch (controller.lifeState) {
      LifeState.active => [
        _StateAction(
          label: '模拟临时失能',
          icon: Icons.health_and_safety_outlined,
          onPressed: () =>
              _confirmTransition(context, LifeState.incapacitated, '人工模拟临时失能'),
        ),
        _StateAction(
          label: '模拟身故',
          icon: Icons.flag_outlined,
          onPressed: () =>
              _confirmTransition(context, LifeState.deceased, '人工模拟身故'),
        ),
      ],
      LifeState.incapacitated => [
        _StateAction(
          label: '恢复健康',
          icon: Icons.favorite_outline,
          onPressed: () =>
              _confirmTransition(context, LifeState.active, '从临时失能恢复'),
        ),
        _StateAction(
          label: '转为身故',
          icon: Icons.flag_outlined,
          onPressed: () =>
              _confirmTransition(context, LifeState.deceased, '人工模拟身故'),
        ),
      ],
      LifeState.deceased => [
        _StateAction(
          label: '重置演示',
          icon: Icons.restart_alt,
          onPressed: () async => runUiAction(
            context,
            controller.resetLifeStateSimulation,
            success: '本机模拟已重置',
          ),
        ),
      ],
    };
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: actions
          .map(
            (action) => FilledButton.tonalIcon(
              onPressed: controller.isBusy ? null : action.onPressed,
              icon: Icon(action.icon),
              label: Text(action.label),
            ),
          )
          .toList(),
    );
  }

  Future<void> _confirmTransition(
    BuildContext context,
    LifeState target,
    String reason,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('模拟切换到“${target.label}”？'),
        content: const Text('这只改变本机模拟状态，不会通知他人。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('确认模拟'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      if (context.mounted) {
        await runUiAction(
          context,
          () => controller.transitionLifeState(target, reason: reason),
        );
      }
    }
  }
}

class _StateAction {
  const _StateAction({
    required this.label,
    required this.icon,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
}
