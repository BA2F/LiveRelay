import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../design_system/atoms.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/credential_dialogs.dart';

class RecyclePage extends StatelessWidget {
  const RecyclePage({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(title: const Text('回收区')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('删除后内容、来源、历史和原有授权仍加密保留。恢复后原有授权会继续生效。原件始终可在“全部原件”找到。'),
          const SizedBox(height: 16),
          if (controller.recycledCards.isEmpty &&
              controller.recycledCredentials.isEmpty)
            const EmptyState(
              icon: Icons.restore_from_trash_outlined,
              title: '回收区是空的',
              message: '移入回收区的卡片和密码会显示在这里。',
            ),
          for (final card in controller.recycledCards)
            Card(
              child: ListTile(
                title: Text(card.title),
                subtitle: const Text('卡片 · 点击查看内容、来源与历史'),
                onTap: () => showCardDetails(context, controller, card),
                trailing: IconButton(
                  tooltip: '恢复卡片',
                  icon: const Icon(Icons.restore),
                  onPressed: controller.isBusy
                      ? null
                      : () => runUiAction(
                          context,
                          () => controller.restoreCard(card.id),
                          success: '已恢复卡片',
                        ),
                ),
              ),
            ),
          for (final entry in controller.recycledCredentials)
            Card(
              child: ListTile(
                title: Text(entry.title),
                subtitle: const Text('密码 · 默认遮挡'),
                onTap: () => showCredentialDetails(context, controller, entry),
                trailing: IconButton(
                  tooltip: '恢复密码',
                  icon: const Icon(Icons.restore),
                  onPressed: controller.isBusy
                      ? null
                      : () => runUiAction(
                          context,
                          () => controller.restoreCredential(entry.id),
                          success: '已恢复密码',
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
