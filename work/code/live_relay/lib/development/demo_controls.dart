import 'dart:io';

import 'package:flutter/material.dart';

import '../application/app_controller.dart';
import '../application/device_capabilities.dart';
import '../core/ports/development_controls.dart';
import '../presentation/pages/recipient_page.dart';
import 'demo_drill_page.dart';

class DemoControls extends ChangeNotifier implements DevelopmentControls {
  DemoControls(this.root);
  final Directory root;
  final navigatorKey = GlobalKey<NavigatorState>();
  late AppController controller;
  DateTime now = DateTime.utc(2026, 10, 3, 12);
  bool expanded = false;
  String? error;
  @override
  void activate() {
    expanded = !expanded;
    notifyListeners();
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
      error = null;
    } catch (e) {
      error = '$e';
    }
    notifyListeners();
  }

  Widget buildOverlay(BuildContext context, Widget child) => AnimatedBuilder(
    animation: this,
    builder: (context, _) => Stack(
      children: [
        child,
        Positioned(
          top: 8,
          right: 8,
          child: SafeArea(
            child: Card(
              color: Colors.amber.shade100,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 360,
                    maxHeight: MediaQuery.sizeOf(context).height - 64,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Expanded(
                              child: Text(
                                '独立演示 · 虚构资料',
                                style: TextStyle(color: Colors.black),
                              ),
                            ),
                            IconButton(
                              onPressed: activate,
                              icon: Icon(
                                expanded ? Icons.expand_less : Icons.tune,
                              ),
                              color: Colors.black,
                            ),
                          ],
                        ),
                        if (expanded) ...[
                          Text(
                            '模拟时间：${now.toIso8601String()}\n所有者：Demo-only-2026\n接收者：Recipient-demo-2026',
                            style: const TextStyle(color: Colors.black),
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () {
                                  now = now.add(const Duration(days: 30));
                                  notifyListeners();
                                },
                                child: const Text('时间 +30 天'),
                              ),
                              TextButton(
                                onPressed: () {
                                  now = DateTime.utc(2026, 10, 3, 12);
                                  notifyListeners();
                                },
                                child: const Text('重置时间'),
                              ),
                            ],
                          ),
                          TextButton(
                            onPressed: () => run(
                              () => navigatorKey.currentState!.push<void>(
                                MaterialPageRoute(
                                  builder: (_) => const DemoDrillPage(),
                                ),
                              ),
                            ),
                            child: const Text('生命状态演练'),
                          ),
                          DropdownButton<DevicePlatform>(
                            value: controller.capabilities.platform,
                            items: [
                              for (final platform in DevicePlatform.values)
                                DropdownMenuItem(
                                  value: platform,
                                  child: Text('模拟能力：${platform.name}'),
                                ),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                controller.setDemonstrationCapabilities(
                                  DeviceCapabilities(value),
                                );
                              }
                              notifyListeners();
                            },
                          ),
                          Wrap(
                            spacing: 8,
                            children: [
                              TextButton(
                                onPressed: () => run(() async {
                                  if (controller.isUnlocked) {
                                    await controller.lock();
                                  } else {
                                    navigatorKey.currentState?.popUntil(
                                      (route) => route.isFirst,
                                    );
                                    controller.recipient?.lock();
                                    await controller.unlockWithPassword(
                                      'Demo-only-2026',
                                    );
                                  }
                                }),
                                child: const Text('所有者锁定 / 解锁'),
                              ),
                              TextButton(
                                onPressed: () => run(() async {
                                  if (controller.isUnlocked) {
                                    await controller.lock();
                                  }
                                  await navigatorKey.currentState!.push<void>(
                                    MaterialPageRoute(
                                      builder: (_) => RecipientPage(
                                        service: controller.recipient!,
                                      ),
                                    ),
                                  );
                                }),
                                child: const Text('切换接收者'),
                              ),
                            ],
                          ),
                          Text(
                            '目录：${root.path}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.black,
                            ),
                          ),
                          if (error != null)
                            Text(
                              error!,
                              style: const TextStyle(color: Colors.red),
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
