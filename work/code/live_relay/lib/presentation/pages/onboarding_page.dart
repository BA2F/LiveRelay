import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../application/app_preferences.dart';
import '../../application/device_capabilities.dart';
import '../dialogs/backup_dialogs.dart';
import '../dialogs/capability_dialog.dart';
import '../widgets/appearance_settings.dart';
import 'gate_page.dart';
import 'recipient_page.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  bool _busy = false;
  Future<void> _openVault(bool restore) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<AppPreferences>().beginOnboarding();
      if (!mounted) return;
      final controller = context.read<AppController>();
      if (restore) {
        await restoreFromBackup(context, controller);
      } else {
        await Navigator.of(
          context,
        ).push<void>(MaterialPageRoute(builder: (_) => const SetupVaultPage()));
      }
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('无法保存设置，请重试')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferences>();
    final controller = context.watch<AppController>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const RecipientEntryButton(),
                  Icon(
                    Icons.lightbulb_rounded,
                    size: 64,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    '欢迎使用留灯',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text('设置 ${_step + 1} / 3'),
                  const SizedBox(height: 24),
                  if (_step == 0) ...[
                    Text('选择语言', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 12),
                    const ListTile(
                      title: Text('简体中文'),
                      trailing: Icon(Icons.check),
                    ),
                    ListTile(
                      title: const Text('English'),
                      subtitle: const Text('Coming later'),
                      onTap: () => showCapabilityMessage(
                        context,
                        'English',
                        controller.capability(AppFeature.english),
                      ),
                    ),
                  ] else if (_step == 1)
                    AppearanceSettings(preferences: preferences)
                  else ...[
                    Text(
                      '你的资料库',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text('创建新的加密资料库，或从已有加密备份恢复。'),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => _openVault(false),
                      icon: const Icon(Icons.add),
                      label: const Text('创建资料库'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => _openVault(true),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: const Text('恢复已有资料库'),
                    ),
                  ],
                  const SizedBox(height: 28),
                  if (_step < 2)
                    FilledButton(
                      onPressed: () => setState(() => _step++),
                      child: const Text('继续'),
                    ),
                  if (_step > 0)
                    TextButton(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => setState(() => _step--),
                      child: const Text('返回'),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class FinishSetupPage extends StatelessWidget {
  const FinishSetupPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.check_circle_outline, size: 64),
                const SizedBox(height: 24),
                Text('准备好了', style: Theme.of(context).textTheme.headlineLarge),
                const SizedBox(height: 12),
                const Text('资料保存在本机。记得把加密备份另存到设备外，并妥善保存解锁口令。'),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    try {
                      await context.read<AppPreferences>().finishOnboarding();
                    } on Object {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('设置未保存，请重试')),
                        );
                      }
                    }
                  },
                  child: const Text('开始使用'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
