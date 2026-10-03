import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'infrastructure/app_composition.dart';
import 'application/app_preferences.dart';
import 'presentation/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = createAppController();
  await controller.initialize();
  File? preferenceFile;
  try {
    final support = await getApplicationSupportDirectory();
    preferenceFile = File('${support.path}/live_relay/device-preferences.json');
  } on Object {
    // Let the controller's startup failure screen remain reachable.
  }
  final preferences = AppPreferences(preferenceFile);
  await preferences.load(hasExistingVault: controller.header != null);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: controller),
        ChangeNotifierProvider.value(value: preferences),
      ],
      child: const LiveRelayApp(),
    ),
  );
}
