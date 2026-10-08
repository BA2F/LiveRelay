import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'controllers/app_controller.dart';
import '../application/app_preferences.dart';
import 'design_system/app_theme.dart';
import 'pages/gate_page.dart';
import 'pages/security_settings_page.dart';
import 'pages/home_shell.dart';
import 'pages/onboarding_page.dart';
import 'workbench/native_close_guard.dart';

class LiveRelayApp extends StatelessWidget {
  const LiveRelayApp({super.key, this.environmentOverlay, this.navigatorKey});
  final Widget Function(BuildContext context, Widget child)? environmentOverlay;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    final preferences = context.watch<AppPreferences?>();
    return MaterialApp(
      title: '留灯 LiveRelay',
      navigatorKey: navigatorKey,
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: LiveRelayTheme.light(),
      darkTheme: LiveRelayTheme.dark(),
      themeMode: switch (preferences?.appearance) {
        AppearanceMode.light => ThemeMode.light,
        AppearanceMode.dark => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) {
        final media = MediaQuery.of(context);
        // Keep accessibility scaling; the app setting only raises the minimum.
        final minimum = preferences?.readingSize == ReadingSize.large
            ? 1.25
            : 1.0;
        return NativeCloseGuard(
          controller: context.read<AppController>(),
          child: MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(minScaleFactor: minimum),
            ),
            child: environmentOverlay?.call(context, child!) ?? child!,
          ),
        );
      },
      home: Consumer<AppController>(
        builder: (context, controller, _) => switch (controller.sessionState) {
          VaultSessionState.loading => const _LoadingScreen(),
          VaultSessionState.needsSetup =>
            preferences == null
                ? const SetupVaultPage()
                : const OnboardingPage(),
          VaultSessionState.locked => const UnlockVaultPage(),
          VaultSessionState.recovering => const SecuritySettingsPage(
            recovery: true,
          ),
          VaultSessionState.unlocked =>
            preferences != null && !preferences.onboardingComplete
                ? const FinishSetupPage()
                : const HomeShell(),
          VaultSessionState.failure => FailurePage(
            message: controller.lastError ?? '初始化失败',
          ),
        },
      ),
    );
  }
}

class _LoadingScreen extends StatelessWidget {
  const _LoadingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class FailurePage extends StatelessWidget {
  const FailurePage({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 20),
                Text(
                  '无法打开留灯',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 12),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
