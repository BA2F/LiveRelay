import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';

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

  static const _titles = ['记录', '卡片', '密码库', '交接'];

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
            onPressed: () => _showSettings(context, controller),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '锁定 Vault',
            onPressed: controller.isBusy ? null : controller.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          CapturePage(),
          CardsPage(),
          PasswordsPage(),
          HandoffPage(),
        ],
      ),
      floatingActionButton: _index == 0 || _index == 1
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
              Text(
                'Vault 设置',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.enhanced_encryption_outlined),
                title: const Text('整库加密'),
                subtitle: const Text('SQLCipher · Argon2id · AES-256-GCM 密钥封装'),
                trailing: const Icon(Icons.verified, color: Colors.green),
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
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('可选云 AI Provider'),
                subtitle: Text(
                  controller.aiSettings.isConfigured
                      ? '${controller.aiSettings.model} · 默认不上传，每次单独授权'
                      : '未配置；手动整理不受影响',
                ),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await showDialog<void>(
                    context: context,
                    builder: (_) => _AiSettingsDialog(controller: controller),
                  );
                },
              ),
              const Divider(),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.archive_outlined),
                title: const Text('导出加密 .lvault'),
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
                title: const Text('从 .lvault 恢复'),
                subtitle: const Text('验证成功后替换当前 Vault，失败时保留原库'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _restoreVault(context, controller);
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
          const _PasswordPromptDialog(title: '再次验证主密码', actionLabel: '验证'),
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
        if (saved != null && context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('加密 .lvault 已导出')));
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

  Future<void> _restoreVault(
    BuildContext context,
    AppController controller,
  ) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: '选择 LiveRelay 加密备份',
      type: FileType.custom,
      allowedExtensions: const ['lvault'],
    );
    if (picked == null) return;
    if (!context.mounted) {
      await FilePicker.clearTemporaryFiles();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.settings_backup_restore),
        title: const Text('恢复并替换当前 Vault？'),
        content: const Text(
          '应用会先校验格式、密码、完整性和数据库，再原子替换当前 Vault。'
          '恢复成功后当前数据将由备份内容取代。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('继续恢复'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final password = await showDialog<String>(
      context: context,
      builder: (_) =>
          const _PasswordPromptDialog(title: '输入备份的主密码', actionLabel: '验证并恢复'),
    );
    if (password == null || !context.mounted) return;
    final bytes = await picked.readAsBytes();
    try {
      await controller.restoreVault(bytes, password);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Vault 已从加密备份恢复')));
      }
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(controller.lastError ?? '恢复失败')));
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
      try {
        await FilePicker.clearTemporaryFiles();
      } on Object {
        // Cleanup is retried on next app start on unsupported implementations.
      }
    }
  }
}

class _AiSettingsDialog extends StatefulWidget {
  const _AiSettingsDialog({required this.controller});

  final AppController controller;

  @override
  State<_AiSettingsDialog> createState() => _AiSettingsDialogState();
}

class _AiSettingsDialogState extends State<_AiSettingsDialog> {
  late final _endpoint = TextEditingController(
    text: widget.controller.aiSettings.endpoint.isEmpty
        ? 'https://api.openai.com/v1/chat/completions'
        : widget.controller.aiSettings.endpoint,
  );
  late final _model = TextEditingController(
    text: widget.controller.aiSettings.model,
  );
  final _apiKey = TextEditingController();
  bool _busy = false;
  bool _showKey = false;
  String? _error;

  @override
  void dispose() {
    _endpoint.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.controller.saveAiSettings(
        endpoint: _endpoint.text,
        model: _model.text,
        apiKey: _apiKey.text.isEmpty ? null : _apiKey.text,
      );
      if (mounted) Navigator.pop(context);
    } on Object {
      if (mounted) {
        setState(() => _error = widget.controller.lastError ?? '保存失败');
      }
    } finally {
      _apiKey.clear();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    icon: const Icon(Icons.auto_awesome_outlined),
    title: const Text('OpenAI-compatible Provider'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('默认关闭。配置不代表授权；每次外发前仍会展示范围并要求单次确认。'),
          const SizedBox(height: 16),
          TextField(
            controller: _endpoint,
            enabled: !_busy,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'HTTPS Chat Completions Endpoint',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '模型名称'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _apiKey,
            enabled: !_busy,
            obscureText: !_showKey,
            decoration: InputDecoration(
              labelText: widget.controller.aiSettings.hasApiKey
                  ? 'API Key（留空则保留原值）'
                  : 'API Key',
              suffixIcon: IconButton(
                onPressed: () => setState(() => _showKey = !_showKey),
                icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    ),
    actions: [
      if (widget.controller.aiSettings.isConfigured)
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  await widget.controller.clearAiSettings();
                  if (context.mounted) Navigator.pop(context);
                },
          child: const Text('清除配置'),
        ),
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('安全保存')),
    ],
  );
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog({required this.title, required this.actionLabel});

  final String title;
  final String actionLabel;

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  final _text = TextEditingController();

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _text,
        obscureText: true,
        autofocus: true,
        onSubmitted: (_) => Navigator.pop(context, _text.text),
        decoration: const InputDecoration(labelText: '主密码或中文词组'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
