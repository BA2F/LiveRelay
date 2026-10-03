import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../../application/app_preferences.dart';
import '../../application/device_capabilities.dart';
import '../dialogs/capability_dialog.dart';
import '../dialogs/vault_settings_dialog.dart';
import '../widgets/appearance_settings.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});
  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final preferences = context.watch<AppPreferences?>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(child: Icon(Icons.person_outline)),
                SizedBox(height: 12),
                Text(
                  '本人',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
                ),
                SizedBox(height: 4),
                Text('当前身份：资料库所有者'),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        if (preferences != null) AppearanceSettings(preferences: preferences),
        const SizedBox(height: 16),
        ListTile(
          leading: const Icon(Icons.language),
          title: const Text('语言'),
          subtitle: const Text('简体中文'),
          onTap: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('语言'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
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
        const Divider(),
        for (final item in [
          (AppFeature.agent, 'Agent', Icons.auto_awesome_outlined),
          (AppFeature.speechInput, '语音输入', Icons.keyboard_voice_outlined),
          (AppFeature.checkIn, '报平安与自动交接', Icons.favorite_outline),
          (AppFeature.partialBackup, '拆分备份', Icons.inventory_2_outlined),
        ])
          ListTile(
            leading: Icon(item.$3),
            title: Text(item.$2),
            subtitle: Text(controller.capability(item.$1).message),
            onTap: () => showCapabilityMessage(
              context,
              item.$2,
              controller.capability(item.$1),
            ),
          ),
        const Divider(),
        const ListTile(
          leading: Icon(Icons.lightbulb_outline),
          title: Text('留灯 LiveRelay'),
          subtitle: Text('1.0.0'),
        ),
      ],
    );
  }
}
