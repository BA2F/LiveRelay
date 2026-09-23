import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'application/app_controller.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = AppController();
  await controller.initialize();
  runApp(
    ChangeNotifierProvider.value(
      value: controller,
      child: const LiveRelayApp(),
    ),
  );
}
