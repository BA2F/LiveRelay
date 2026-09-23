import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../core/domain/entities.dart';
import '../design_system/atoms.dart';
import '../model_labels.dart';

class HandoffPage extends StatelessWidget {
  const HandoffPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: scheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.science_outlined, color: scheme.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'MVP 人工模拟：这里不做真实失能或身故核验，也不授予银行、继承等法律处置权。',
                  style: TextStyle(color: scheme.onTertiaryContainer),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前生命状态', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 14),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: scheme.primaryContainer,
                      child: Icon(
                        controller.lifeState.icon,
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        controller.lifeState.label,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _TransitionActions(controller: controller),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        PageSection(
          title: 'Executor View',
          subtitle: controller.lifeState == LifeState.active
              ? '仅在模拟失能或身故后展示明确授权的信息'
              : '只展示每条信息在当前状态下被明确授权的层级',
          child: _ExecutorView(controller: controller),
        ),
        const SizedBox(height: 24),
        PageSection(
          title: '状态历史',
          subtitle: '每次模拟转换都留下审计事件',
          child: controller.lifeStateHistory.isEmpty
              ? const EmptyState(
                  icon: Icons.history,
                  title: '还没有状态变化',
                  message: '长期不活动不会在这里被自动解释为死亡。',
                )
              : Card(
                  child: Column(
                    children: controller.lifeStateHistory
                        .map(
                          (event) => ListTile(
                            leading: const Icon(Icons.timeline),
                            title: Text(
                              '${event.from.label} → ${event.to.label}',
                            ),
                            subtitle: Text(
                              '${event.reason}\n${DateFormat('yyyy-MM-dd HH:mm').format(event.occurredAt.toLocal())}',
                            ),
                            isThreeLine: true,
                          ),
                        )
                        .toList(),
                  ),
                ),
        ),
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
          onPressed: () async => controller.resetLifeStateSimulation(),
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
        content: const Text('这只改变本机 MVP 的演示状态，并按已有策略计算可见范围。'),
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
      await controller.transitionLifeState(target, reason: reason);
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

class _ExecutorView extends StatelessWidget {
  const _ExecutorView({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    if (controller.lifeState == LifeState.active) {
      return const EmptyState(
        icon: Icons.visibility_off_outlined,
        title: 'Executor View 尚未开启',
        message: 'Owner 正常使用时，不向演示执行人释放信息。',
      );
    }
    final cards = controller.executorCards;
    final credentials = controller.executorCredentials;
    if (cards.isEmpty && credentials.isEmpty) {
      return const EmptyState(
        icon: Icons.shield_outlined,
        title: '没有被授权的信息',
        message: '新卡片和密码条目默认仅本人可见，组合和盒子不会扩大权限。',
      );
    }
    return Column(
      children: [
        for (final card in cards) ...[
          _ReleasedCard(
            card: card,
            level: controller.executorVisibilityFor(card),
          ),
          const SizedBox(height: 10),
        ],
        for (final entry in credentials) ...[
          _ReleasedCredential(
            entry: entry,
            level: controller.executorCredentialVisibilityFor(entry),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ReleasedCard extends StatelessWidget {
  const _ReleasedCard({required this.card, required this.level});

  final LifeCard card;
  final VisibilityLevel level;

  @override
  Widget build(BuildContext context) {
    final content = switch (level) {
      VisibilityLevel.hidden => '',
      VisibilityLevel.existence => '存在一条此类信息，内容未授权。',
      VisibilityLevel.summary =>
        card.content.length > 80
            ? '${card.content.substring(0, 80)}…'
            : card.content,
      _ => card.content,
    };
    return Card(
      child: ListTile(
        leading: const Icon(Icons.description_outlined),
        title: Text(card.title),
        subtitle: Text(content),
        trailing: StatusPill(label: level.label),
      ),
    );
  }
}

class _ReleasedCredential extends StatelessWidget {
  const _ReleasedCredential({required this.entry, required this.level});

  final CredentialEntry entry;
  final VisibilityLevel level;

  @override
  Widget build(BuildContext context) {
    final canSeeSecret = level.index >= VisibilityLevel.secret.index;
    final details = switch (level) {
      VisibilityLevel.hidden => '',
      VisibilityLevel.existence => '存在此账户，具体信息未授权。',
      VisibilityLevel.summary => '${entry.username} ${entry.website}'.trim(),
      VisibilityLevel.full =>
        entry.notes.isEmpty ? entry.username : entry.notes,
      _ => '${entry.username}\nSecret：${entry.secret}',
    };
    return Card(
      child: ListTile(
        leading: Icon(canSeeSecret ? Icons.key : Icons.key_off_outlined),
        title: Text(entry.title),
        subtitle: Text(details),
        trailing: StatusPill(label: level.label),
      ),
    );
  }
}
