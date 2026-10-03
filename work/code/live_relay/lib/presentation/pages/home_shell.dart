import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../application/app_controller.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/credential_dialogs.dart';
import 'cards_page.dart';
import 'capture_page.dart';
import 'handoff_page.dart';
import 'passwords_page.dart';
import 'profile_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  static const _destinations = [
    ('记录', Icons.edit_note_outlined),
    ('卡片', Icons.view_agenda_outlined),
    ('密码库', Icons.key_outlined),
    ('交接', Icons.how_to_reg_outlined),
    ('我的', Icons.person_outline),
  ];
  Future<void> _newCard(AppController controller) async {
    final password = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notes),
            title: const Text('信息卡片'),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: const Text('密码卡片'),
            onTap: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
    if (password == null || !mounted) return;
    if (password) {
      await showCredentialEditor(context, controller);
    } else {
      await showCardEditor(context, controller);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<AppController>();
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final content = IndexedStack(
      index: _index,
      children: [
        const CapturePage(),
        const CardsPage(),
        PasswordsPage(active: _index == 2),
        const HandoffPage(),
        const ProfilePage(),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: Text(_index == 3 ? '交接准备' : _destinations[_index].$1),
        actions: [
          if (controller.isBusy)
            const Padding(
              padding: EdgeInsets.all(12),
              child: Center(
                child: SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          IconButton(
            tooltip: '设置',
            onPressed: () => setState(() => _index = 4),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: '锁定加密资料库',
            onPressed: controller.isBusy ? null : controller.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: wide
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: _index,
                  labelType: NavigationRailLabelType.all,
                  onDestinationSelected: (index) =>
                      setState(() => _index = index),
                  destinations: [
                    for (final destination in _destinations)
                      NavigationRailDestination(
                        icon: Icon(destination.$2),
                        label: Text(destination.$1),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1120),
                      child: content,
                    ),
                  ),
                ),
              ],
            )
          : content,
      floatingActionButton: _index == 1
          ? FloatingActionButton.extended(
              onPressed: controller.isBusy ? null : () => _newCard(controller),
              icon: const Icon(Icons.add),
              label: const Text('新建卡片'),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                for (final destination in _destinations)
                  NavigationDestination(
                    icon: Icon(destination.$2),
                    label: destination.$1,
                  ),
              ],
            ),
    );
  }
}
