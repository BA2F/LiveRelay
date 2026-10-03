import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import '../../application/app_controller.dart';
import '../../application/device_capabilities.dart';
import '../pages/recycle_page.dart';
import '../pages/security_settings_page.dart';
import 'backup_dialogs.dart';
import 'ai_settings_dialog.dart';
import 'capability_dialog.dart';

Future<void> showVaultSettings(
  BuildContext context,
  AppController controller,
) async {
  await showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => FractionallySizedBox(
      heightFactor: 0.9,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('资料库设置', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.enhanced_encryption_outlined),
              title: const Text('整库加密'),
              subtitle: const Text('信息已加密保存在本机，默认仅本人可见'),
              trailing: const Icon(Icons.lock_outline),
            ),
            if (controller.supportsModernSecurity)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.security),
                title: const Text('解锁方式与独立恢复'),
                subtitle: const Text('更换密码、密钥文件、指纹与组合策略'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) => const SecuritySettingsPage(),
                    ),
                  );
                },
              ),
            if (controller.biometricAvailable &&
                controller.header?.formatVersion == 1)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.fingerprint),
                title: const Text('指纹解锁'),
                subtitle: const Text('使用本机生物识别解锁'),
                value: controller.header?.biometricEnabled ?? false,
                onChanged: (enabled) async {
                  if (enabled) {
                    final password = await _askForPassword(sheetContext);
                    if (password == null) return;
                    try {
                      await controller.enableBiometricWithPassword(password);
                    } on Object {
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text(controller.lastError ?? '启用失败'),
                          ),
                        );
                      }
                    }
                  } else {
                    await controller.setBiometricEnabled(false);
                  }
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                },
              ),
            if (!controller.biometricAvailable)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.fingerprint),
                title: const Text('生物识别解锁'),
                subtitle: Text(
                  controller.capability(AppFeature.biometric).message,
                ),
                onTap: () => showCapabilityMessage(
                  sheetContext,
                  '生物识别解锁',
                  controller.capability(AppFeature.biometric),
                ),
              ),
            const Divider(),
            Text('备份状态', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              controller.lastBackupExport == null
                  ? '尚无成功导出记录'
                  : '上次成功导出：${DateFormat('yyyy-MM-dd HH:mm').format(controller.lastBackupExport!.toLocal())}',
            ),
            const Text('本机保存不等于设备外备份。导出记录只表示文件已保存；请另存到设备外，并验证能恢复。'),
            const SizedBox(height: 8),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.archive_outlined),
              title: const Text('导出加密备份'),
              subtitle: const Text('验证解锁口令后保存完整备份'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await _exportVault(context, controller);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                Icons.settings_backup_restore,
                color: Theme.of(context).colorScheme.error,
              ),
              title: const Text('从加密备份恢复'),
              subtitle: const Text('验证成功后替换当前加密资料库，失败时保留原库'),
              onTap: () async {
                Navigator.pop(sheetContext);
                await restoreFromBackup(context, controller);
              },
            ),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.restore_from_trash_outlined),
              title: Text(
                '回收区 · ${controller.recycledCards.length + controller.recycledCredentials.length} 条',
              ),
              subtitle: const Text('查看并恢复已删除的卡片与密码，历史仍保留'),
              onTap: () {
                Navigator.pop(sheetContext);
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => const RecyclePage()),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.auto_awesome_outlined),
              title: const Text('可选 AI 服务'),
              subtitle: Text(
                controller.aiSettings.isConfigured
                    ? '${controller.aiSettings.model} · 默认不上传，每次单独授权'
                    : '未配置；手动整理不受影响',
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                await showDialog<void>(
                  context: context,
                  builder: (_) => AiSettingsDialog(controller: controller),
                );
              },
            ),
            const Divider(),
            FilledButton.tonalIcon(
              onPressed: () async {
                Navigator.pop(sheetContext);
                await controller.lock();
              },
              icon: const Icon(Icons.lock_outline),
              label: const Text('立即锁定'),
            ),
          ],
        ),
      ),
    ),
  );
}

Future<String?> _askForPassword(BuildContext context) async {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        const PasswordPromptDialog(title: '再次验证主密码', actionLabel: '验证'),
  );
}

Future<void> _exportVault(
  BuildContext context,
  AppController controller,
) async {
  final password = await _askForPassword(context);
  if (password == null || !context.mounted) return;
  try {
    final bytes = await controller.exportVault(password);
    try {
      final stamp = DateTime.now()
          .toIso8601String()
          .substring(0, 19)
          .replaceAll(RegExp(r'[:T]'), '-');
      final saved = await FilePicker.saveFile(
        fileName: 'LiveRelay-$stamp.lvault',
        bytes: bytes,
        mimeType: 'application/vnd.liverelay.vault',
        type: FileType.custom,
        allowedExtensions: const ['lvault'],
        dialogTitle: '导出 LiveRelay 加密备份',
      );
      if (saved != null) await controller.markBackupExported();
      if (saved != null && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('加密备份已导出；请另存到设备外并验证恢复')));
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  } on Object {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(controller.lastError ?? '导出失败')));
    }
  }
}
