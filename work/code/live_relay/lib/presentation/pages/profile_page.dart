import '../widgets/liverelay_logo.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/ports/development_controls.dart';

import '../controllers/app_controller.dart';
import '../../application/app_preferences.dart';
import '../../application/device_capabilities.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/capability_dialog.dart';
import '../dialogs/vault_settings_dialog.dart';
import '../widgets/appearance_settings.dart';
import 'agent_page.dart';
import 'cradle_page.dart';
import 'speech_input_page.dart';
import 'identity_page.dart';
import 'local_backup_page.dart';
import 'device_transfer_page.dart';
import 'recipient_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.onOpenExtensions});
  /// 桌面传入时提供扩展入口；手机端暂不显示。
  final VoidCallback? onOpenExtensions;
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  int taps = 0;
  DateTime? lastTap;
  void versionTap(DevelopmentControls? controls) {
    if (controls == null) return;
    final now = DateTime.now();
    if (lastTap == null ||
        now.difference(lastTap!) > const Duration(seconds: 3)) {
      taps = 0;
    }
    lastTap = now;
    if (++taps >= 7) {
      taps = 0;
      controls.activate();
    }
  }

  Future<void> _setLanguage(BuildContext context, AppLanguage language) async {
    try {
      await context.read<AppPreferences>().setLanguage(language);
    } on Object {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).settingsSaveFailed)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final preferences = context.watch<AppPreferences?>();
    final l10n = AppLocalizations.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(Icons.person_outline)),
                SizedBox(height: 12),
                Text(
                  controller.ownerProfile['name'] as String,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text('当前身份：资料库所有者'),
              ],
            ),
          ),
        ),
        if (controller.handoff != null)
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('本人身份与接收者'),
            subtitle: const Text('编辑身份资料、验证接收者、限定范围交接'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const IdentityPage()),
            ),
          ),
        if (controller.recipient != null)
          ListenableBuilder(
            listenable: controller.recipient!,
            builder: (context, _) => controller.recipient!.exists
                ? const SizedBox.shrink()
                : ListTile(
                    leading: const Icon(Icons.person_add_alt_1_outlined),
                    title: Text(l10n.recipientCreate),
                    subtitle: const Text('在本机建立独立只读身份，用于接收别人的交接'),
                    onTap: () => openRecipientEntry(context),
                  ),
          ),
        const SizedBox(height: 24),
        if (preferences != null) AppearanceSettings(preferences: preferences),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.language),
          title: Text(l10n.languageTitle),
          subtitle: Text(
            preferences?.language == AppLanguage.en ? 'English' : '简体中文',
          ),
          onTap: () => showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: Text(AppLocalizations.of(dialogContext).languageTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    title: const Text('简体中文'),
                    trailing: preferences?.language == AppLanguage.zh
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _setLanguage(dialogContext, AppLanguage.zh),
                  ),
                  ListTile(
                    title: const Text('English'),
                    trailing: preferences?.language == AppLanguage.en
                        ? const Icon(Icons.check)
                        : null,
                    onTap: () => _setLanguage(dialogContext, AppLanguage.en),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(AppLocalizations.of(dialogContext).done),
                ),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.settings_outlined),
          title: const Text('资料库设置'),
          subtitle: const Text('解锁、安全、备份与 AI 服务'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showVaultSettings(context, controller),
        ),
        if (widget.onOpenExtensions != null)
          ListTile(
            leading: const Icon(Icons.extension_outlined),
            title: const Text('扩展'),
            subtitle: const Text('安装与管理资料视图扩展'),
            trailing: const Icon(Icons.chevron_right),
            onTap: widget.onOpenExtensions,
          ),
        ListTile(
          leading: const Icon(Icons.import_export),
          title: const Text('设备间搬运'),
          subtitle: const Text('数据线 / 局域网 / WebDAV 目录：整库导出与导入'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push<void>(
            MaterialPageRoute(builder: (_) => const DeviceTransferPage()),
          ),
        ),
        const Divider(),
        for (final item in [
          (AppFeature.agent, 'Agent', Icons.auto_awesome_outlined),
          (AppFeature.speechInput, '语音识别与转写', Icons.keyboard_voice_outlined),
          (AppFeature.checkIn, '报平安与自动交接', Icons.favorite_outline),
          (AppFeature.partialBackup, '拆分备份', Icons.inventory_2_outlined),
        ])
          ListTile(
            leading: Icon(item.$3),
            title: Text(item.$2),
            subtitle: Text(controller.capability(item.$1).message),
            onTap: () {
              final page = switch (item.$1) {
                AppFeature.agent => const AgentPage(),
                AppFeature.speechInput => const SpeechInputPage(),
                AppFeature.checkIn => const CradlePage(),
                AppFeature.partialBackup => const LocalBackupPage(),
                _ => null,
              };
              if (page == null) {
                showCapabilityMessage(
                  context,
                  item.$2,
                  controller.capability(item.$1),
                );
              } else {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(builder: (_) => page),
                );
              }
            },
          ),
        const Divider(),
        ListTile(
          leading: const LiveRelayLogo(size: 24),
          title: const Text('留灯 LiveRelay'),
          subtitle: const Text('1.0.0-beta.2'),
          onTap: () => versionTap(context.read<DevelopmentControls?>()),
        ),
      ],
    );
  }
}
