import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import '../application/app_controller.dart';
import 'design_system/app_theme.dart';
import 'pages/gate_page.dart';
import 'pages/home_shell.dart';

class LiveRelayApp extends StatelessWidget {
  const LiveRelayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '留灯 LiveRelay',
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      debugShowCheckedModeBanner: false,
      theme: LiveRelayTheme.light(),
      darkTheme: LiveRelayTheme.dark(),
      themeMode: ThemeMode.system,
      home: Consumer<AppController>(
        builder: (context, controller, _) => switch (controller.sessionState) {
          VaultSessionState.loading => const _LoadingScreen(),
          VaultSessionState.needsSetup => const SetupVaultPage(),
          VaultSessionState.locked => const UnlockVaultPage(),
          VaultSessionState.unlocked => const HomeShell(),
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
