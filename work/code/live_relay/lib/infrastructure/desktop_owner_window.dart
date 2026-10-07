import 'dart:io';
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

/// An explicit child-window tool request presents this process's own window.
/// The Linux runner supplies a current X11 timestamp for the window manager.
const _ownerChannel = MethodChannel('liverelay/owner_window');

Future<String> nativeDesktopBackend() async => Platform.isLinux
    ? await _ownerChannel.invokeMethod<String>('backend') ?? 'other'
    : 'other';

/// An ephemeral compositor token for this window's current user interaction.
Future<String?> ownerWindowActivationToken() async {
  if (!Platform.isLinux) return null;
  try {
    return await _ownerChannel.invokeMethod<String>('requestActivationToken');
  } on PlatformException {
    return null;
  } on MissingPluginException {
    return null;
  }
}

Future<bool> activateOwnerWindow({String? activationToken}) async {
  await windowManager.ensureInitialized();
  if (Platform.isLinux) {
    await _ownerChannel.invokeMethod('activate', activationToken);
  } else {
    if (await windowManager.isMinimized()) await windowManager.restore();
    await windowManager.show();
    await windowManager.focus();
  }
  for (var tick = 0; tick < 10; tick++) {
    if (await windowManager.isFocused()) return true;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
  return await windowManager.isFocused();
}
