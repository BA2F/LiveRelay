import 'package:flutter/material.dart';

import '../../application/app_preferences.dart';

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
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('设置未保存，请重试')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('外观', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final mode in AppearanceMode.values)
              ChoiceChip(
                label: Text(switch (mode) {
                  AppearanceMode.system => '跟随系统',
                  AppearanceMode.light => '浅色',
                  AppearanceMode.dark => '深色',
                }),
                selected: preferences.appearance == mode,
                onSelected: (_) =>
                    _save(context, () => preferences.setAppearance(mode: mode)),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('文字大小', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final size in ReadingSize.values)
              ChoiceChip(
                label: Text(size == ReadingSize.medium ? '中等（默认）' : '大'),
                selected: preferences.readingSize == size,
                onSelected: (_) =>
                    _save(context, () => preferences.setAppearance(size: size)),
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
                Text('留灯', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                const Text('把重要信息留在你能掌控的地方。'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
