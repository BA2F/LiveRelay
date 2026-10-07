import 'dart:io';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// An explicit child-window tool request presents this process's own window.
/// The Linux runner supplies a current X11 timestamp for the window manager.
Future<void> activateOwnerWindow() async {
  if (Platform.isLinux) {
    await const MethodChannel('liverelay/owner_window')
        .invokeMethod('activate');
    return;
  }
  await windowManager.ensureInitialized();
  if (await windowManager.isMinimized()) await windowManager.restore();
  await windowManager.show();
  await windowManager.focus();
}
