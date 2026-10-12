import 'package:flutter/material.dart';

import '../../core/ai/outbound_consent.dart';
import '../controllers/app_controller.dart';

/// 发送前的首次确认闸门。已授权直接放行；未授权时弹一次说明
/// “以后这类内容默认发送”，确认后记录授权；取消返回 false，不发送。
Future<bool> ensureOutboundConsent(
  BuildContext context,
  AppController controller, {
  required OutboundDestination destination,
  required OutboundKind kind,
  List<String> attachmentLines = const [],
}) async {
  if (controller.outboundConsent.granted(destination, kind)) return true;
  final confirmed = await showOutboundFirstSendDialog(
    context,
    destination: destination,
    kind: kind,
    attachmentLines: attachmentLines,
  );
  if (confirmed != true || !controller.isUnlocked) return false;
  try {
    await controller.grantOutbound(destination, kind);
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('授权记录保存失败，下次发送会再确认一次')),
      );
    }
  }
  return true;
}

Future<bool?> showOutboundFirstSendDialog(
  BuildContext context, {
  required OutboundDestination destination,
  required OutboundKind kind,
  List<String> attachmentLines = const [],
}) => showDialog<bool>(
  context: context,
  builder: (dialogContext) => AlertDialog(
    icon: Icon(
      kind == OutboundKind.attachment
          ? Icons.attach_file
          : Icons.cloud_upload_outlined,
    ),
    title: Text(
      kind == OutboundKind.attachment
          ? '首次向 ${destination.label} 发送附件？'
          : '首次向 ${destination.label} 发送内容？',
    ),
    content: SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (kind == OutboundKind.attachment) ...[
              const Text('附件按原始内容发送，不做敏感内容替换：'),
              for (final line in attachmentLines) Text('• $line'),
              const SizedBox(height: 12),
              const Text('确认后，以后向这个服务发送附件默认直接发送，不再每次询问。可在 AI 服务设置中收回授权。'),
            ] else ...[
              const Text('发送的是本机脱敏后的文字：标记为敏感的行只以占位符发送，附件与密码库正文不在范围内。'),
              const SizedBox(height: 12),
              const Text('确认后，以后向这个服务发送内容默认直接发送，不再每次询问。可在 AI 服务设置中收回授权。'),
            ],
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(dialogContext, false),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(dialogContext, true),
        child: const Text('发送并记住'),
      ),
    ],
  ),
);

/// 输入区旁边的“将发送”常驻面板：把实际外发内容放在发送按钮同一屏，
/// 所见即所发，日常发送不再弹窗。内容始终展开，不做折叠。
class OutboundPreviewPanel extends StatelessWidget {
  const OutboundPreviewPanel({
    super.key,
    required this.service,
    required this.children,
  });
  final String service;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.outbox_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '将发送 · $service',
                    style: theme.textTheme.labelLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }
}
