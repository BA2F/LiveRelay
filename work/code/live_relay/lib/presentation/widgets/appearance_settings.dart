import 'package:flutter/material.dart';

import '../../application/app_preferences.dart';
import '../../l10n/app_localizations.dart';

class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.preferences});
  final AppPreferences preferences;
  Future<void> _save(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
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
    final l10n = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(l10n.appearanceTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final mode in AppearanceMode.values)
                ChoiceChip(
                  label: Text(switch (mode) {
                    AppearanceMode.system => l10n.appearanceSystem,
                    AppearanceMode.light => l10n.appearanceLight,
                    AppearanceMode.dark => l10n.appearanceDark,
                  }),
                  selected: preferences.appearance == mode,
                  onSelected: (_) => _save(
                    context,
                    () => preferences.setAppearance(mode: mode),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Text(l10n.readingSizeTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final size in ReadingSize.values)
                ChoiceChip(
                  label: Text(
                    size == ReadingSize.medium
                        ? l10n.readingSizeMedium
                        : l10n.readingSizeLarge,
                  ),
                  selected: preferences.readingSize == size,
                  onSelected: (_) => _save(
                    context,
                    () => preferences.setAppearance(size: size),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.brandName,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(l10n.brandTagline),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
