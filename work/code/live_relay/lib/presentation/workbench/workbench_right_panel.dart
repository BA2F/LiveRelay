import 'package:flutter/material.dart';

import '../controllers/app_controller.dart';

/// 右栏：跟着当前标签走的只读透镜——像 VSCode 的 Timeline / Find-References
/// 一样呈现信息、点击跳转定位；一切写操作留在中央编辑区。
/// 卡片对象（card/、review/、history/）显示来源、历史与引用；
/// 原件（source/）显示基本信息与被引用情况；其余标签显示空态占位。
class WorkbenchRightPanel extends StatelessWidget {
  const WorkbenchRightPanel({
    super.key,
    required this.controller,
    required this.activeView,
    required this.onOpen,
  });

  static const double width = 320;

  final AppController controller;
  final String? activeView;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) => const _LensEmpty();
}

class _LensEmpty extends StatelessWidget {
  const _LensEmpty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('当前标签没有跟随信息', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 6),
          Text(
            '右栏跟随卡片与原件标签，显示来源、历史与引用。',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
