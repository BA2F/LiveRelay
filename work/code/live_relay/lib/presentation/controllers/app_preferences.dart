import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../application/device_preferences_runtime.dart';
import '../../core/device/device_preferences.dart';
export '../../core/device/device_preferences.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences(this.runtime) {
    _subscription = runtime.changes.listen((_) => notifyListeners());
  }
  final DevicePreferencesRuntime runtime;
  late final StreamSubscription<DevicePreferences> _subscription;
  AppearanceMode get appearance => runtime.state.appearance;
  ReadingSize get readingSize => runtime.state.readingSize;
  bool get onboardingStarted => runtime.state.onboardingStarted;
  bool get onboardingComplete => runtime.state.onboardingComplete;
  String? get desktopPreset => runtime.state.desktopPreset;
  Future<void> load({required bool hasExistingVault}) =>
      runtime.load(hasExistingVault: hasExistingVault);
  Future<void> setAppearance({AppearanceMode? mode, ReadingSize? size}) =>
      runtime.setAppearance(mode: mode, size: size);
  Future<void> beginOnboarding() => runtime.beginOnboarding();
  Future<void> finishOnboarding() => runtime.finishOnboarding();
  Future<void> setDesktopPreset(String? preset) =>
      runtime.setDesktopPreset(preset);
  @override
  void dispose() {
    unawaited(_subscription.cancel());
    runtime.dispose();
    super.dispose();
  }
}
