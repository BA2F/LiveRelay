import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../dialogs/backup_dialogs.dart';
import '../dialogs/ai_settings_dialog.dart';
import 'recycle_page.dart';

import '../../application/app_controller.dart';
import '../dialogs/card_dialogs.dart';
import 'cards_page.dart';
import 'capture_page.dart';
import 'handoff_page.dart';
import 'passwords_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const _titles = ['记录', '卡片', '密码库', '交接准备'];

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          if (controller.isBusy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: '设置',
            onPressed: controller.isBusy
                ? null
                : () => _showSettings(context, controller),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '锁定加密资料库',
            onPressed: controller.isBusy ? null : controller.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: [
          const CapturePage(),
          const CardsPage(),
          PasswordsPage(active: _index == 2),
          const HandoffPage(),
        ],
      ),
      floatingActionButton: _index == 1
          ? FloatingActionButton.extended(
              onPressed: controller.isBusy
                  ? null
                  : () => showCardEditor(context, controller),
              icon: const Icon(Icons.add),
              label: const Text('新建记录'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: '记录',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_agenda_outlined),
            selectedIcon: Icon(Icons.view_agenda),
            label: '卡片',
          ),
          NavigationDestination(
            icon: Icon(Icons.key_outlined),
            selectedIcon: Icon(Icons.key),
            label: '密码库',
          ),
          NavigationDestination(
            icon: Icon(Icons.how_to_reg_outlined),
            selectedIcon: Icon(Icons.how_to_reg),
            label: '交接',
          ),
        ],
      ),
    );
  }

  Future<void> _showSettings(
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
              if (controller.biometricAvailable)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(Icons.fingerprint),
                  title: const Text('指纹解锁'),
                  subtitle: const Text('设备密钥槽受 Android Keystore 保护'),
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
                subtitle: const Text('再次验证主密码，导出完整性认证的单体备份'),
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
              const ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text('安全技术详情'),
                children: [
                  Text(
                    'SQLCipher 整库加密 · Argon2id 口令派生 · AES-256-GCM 密钥和原件保护。主密码用于解封随机主密钥；备份清单有完整性认证。',
                  ),
                ],
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
}
