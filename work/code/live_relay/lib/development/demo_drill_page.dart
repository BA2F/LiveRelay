import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../application/app_controller.dart';
import '../core/domain/entities.dart';
import '../presentation/design_system/atoms.dart';
import '../presentation/model_labels.dart';
import '../presentation/pages/handoff_page.dart' show ReleasedContents;

/// 独立演示专属：生命状态演练。正式入口不提供此页，切换只作用于
/// 演示资料库，用于核对释放范围与交接预览。
class DemoDrillPage extends StatelessWidget {
  const DemoDrillPage({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('生命状态演练')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('只在独立演示中出现。切换会更新演示资料库的状态，用于核对释放范围与交接预览。'),
          const SizedBox(height: 16),
          Text(
            '当前状态：${c.lifeState.label}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          _TransitionActions(controller: c),
          const SizedBox(height: 20),
          ReleasedContents(controller: c, scene: c.lifeState),
          const SizedBox(height: 20),
          Text('状态历史', style: Theme.of(context).textTheme.titleLarge),
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
            success: '演示状态已重置',
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
        content: const Text('只改变本演示资料库的状态。'),
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
