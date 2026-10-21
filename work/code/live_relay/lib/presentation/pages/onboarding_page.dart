import '../widgets/liverelay_logo.dart';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/app_controller.dart';
import '../../application/app_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/backup_dialogs.dart';
import '../widgets/appearance_settings.dart';
import 'gate_page.dart';
import 'handoff_view_page.dart';

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).onboardingSaveFailed),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _switchLanguage(AppLanguage language) async {
    try {
      await context.read<AppPreferences>().setLanguage(language);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).onboardingSaveFailed),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferences>();
    final controller = context.watch<AppController>();
    final l10n = AppLocalizations.of(context);
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
                  const Center(child: LiveRelayLogo(size: 64)),
                  const SizedBox(height: 24),
                  Text(
                    l10n.onboardingWelcome,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.onboardingStep(_step + 1)),
                  const SizedBox(height: 24),
                  if (_step == 0) ...[
                    Text(
                      l10n.onboardingChooseLanguage,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      title: const Text('简体中文'),
                      trailing: preferences.language == AppLanguage.zh
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => _switchLanguage(AppLanguage.zh),
                    ),
                    ListTile(
                      title: const Text('English'),
                      trailing: preferences.language == AppLanguage.en
                          ? const Icon(Icons.check)
                          : null,
                      onTap: () => _switchLanguage(AppLanguage.en),
                    ),
                  ] else if (_step == 1)
                    AppearanceSettings(preferences: preferences)
                  else ...[
                    Text(
                      l10n.onboardingYourVault,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => _openVault(false),
                      icon: const Icon(Icons.add),
                      label: Text(l10n.onboardingCreate),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => _openVault(true),
                      icon: const Icon(Icons.settings_backup_restore),
                      label: Text(l10n.onboardingRestore),
                    ),
                    const SizedBox(height: 20),
                    const PickupEntryButton(),
                  ],
                  const SizedBox(height: 28),
                  if (_step < 2)
                    FilledButton(
                      onPressed: () => setState(() => _step++),
                      child: Text(l10n.onboardingContinue),
                    ),
                  if (_step > 0)
                    TextButton(
                      onPressed: _busy || controller.isBusy
                          ? null
                          : () => setState(() => _step--),
                      child: Text(l10n.back),
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
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
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
                  Text(
                    l10n.finishReady,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(l10n.finishMessage),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: () async {
                      try {
                        await context.read<AppPreferences>().finishOnboarding();
                      } on Object {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.settingsSaveFailed)),
                          );
                        }
                      }
                    },
                    child: Text(l10n.finishStart),
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
