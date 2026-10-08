import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../controllers/app_controller.dart';

/// window_manager replaces GTK's Flutter close handler. Route the real native
/// close request through the same save contract as AppLifecycleListener.
class NativeCloseGuard extends StatefulWidget {
  const NativeCloseGuard({
    super.key,
    required this.controller,
    required this.child,
  });
  final AppController controller;
  final Widget child;
  @override
  State<NativeCloseGuard> createState() => _NativeCloseGuardState();
}

class _NativeCloseGuardState extends State<NativeCloseGuard>
    with WindowListener {
  bool _active = false, _closing = false;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    if (!Platform.isLinux) return;
    try {
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
      if (!mounted) return;
      _active = true;
      windowManager.addListener(this);
    } on Object {
      /* Flutter test binding has no native window plugin. */
    }
  }

  @override
  void onWindowClose() => unawaited(_close());
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final result = await widget.controller.desktopExitRequested?.call();
      if (result == AppExitResponse.cancel) return;
      for (final cleanup in List.of(widget.controller.exitCleanups)) {
        await cleanup();
      }
      await windowManager.destroy();
    } on Object {
      /* Keep the window available for a save retry. */
    } finally {
      _closing = false;
    }
  }

  @override
  void dispose() {
    if (_active) windowManager.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
