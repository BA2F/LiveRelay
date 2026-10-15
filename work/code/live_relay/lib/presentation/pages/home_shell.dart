import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../cradle_auto_checkin.dart';
import '../dialogs/card_dialogs.dart';
import '../dialogs/credential_dialogs.dart';
import '../../l10n/app_localizations.dart';
import 'cards_page.dart';
import 'capture_page.dart';
import 'handoff_page.dart';
import 'passwords_page.dart';
import 'profile_page.dart';
import '../workbench/desktop_workbench.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  var _autoCheckInLaunched = false;
  Future<void> _newCard(AppController controller) async {
    final l10n = AppLocalizations.of(context);
    final password = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.notes),
            title: Text(l10n.shellNewCardInfo),
            onTap: () => Navigator.pop(context, false),
          ),
          ListTile(
            leading: const Icon(Icons.key),
            title: Text(l10n.shellNewCardPassword),
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
    if (!_autoCheckInLaunched) {
      _autoCheckInLaunched = true;
      unawaited(maybeAutoCheckIn(controller));
    }
    if (defaultTargetPlatform == TargetPlatform.linux ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS) {
      return const DesktopWorkbench();
    }
    final l10n = AppLocalizations.of(context);
    final destinations = [
      (l10n.tabRecord, Icons.edit_note_outlined),
      (l10n.tabCards, Icons.view_agenda_outlined),
      (l10n.tabPasswords, Icons.key_outlined),
      (l10n.tabHandoff, Icons.how_to_reg_outlined),
      (l10n.tabProfile, Icons.person_outline),
    ];
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
        title: Text(
          _index == 3 ? l10n.shellHandoffTitle : destinations[_index].$1,
        ),
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
            tooltip: l10n.shellSettings,
            onPressed: () => setState(() => _index = 4),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: l10n.shellLock,
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
                    for (final destination in destinations)
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
              label: Text(l10n.shellNewCard),
            )
          : null,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (index) => setState(() => _index = index),
              destinations: [
                for (final destination in destinations)
                  NavigationDestination(
                    icon: Icon(destination.$2),
                    label: destination.$1,
                  ),
              ],
            ),
    );
  }
}
