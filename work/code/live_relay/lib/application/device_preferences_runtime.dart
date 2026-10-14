import 'dart:async';

import '../core/device/device_preferences.dart';
import '../core/ports/device_preferences_repository.dart';

class DevicePreferencesRuntime {
  DevicePreferencesRuntime(this.repository);
  final DevicePreferencesRepository repository;
  DevicePreferences _state = const DevicePreferences();
  DevicePreferences get state => _state;
  final _changes = StreamController<DevicePreferences>.broadcast(sync: true);
  Stream<DevicePreferences> get changes => _changes.stream;
  Future<void> _pending = Future.value();
  bool _disposed = false;
  void _ensureLive() {
    if (_disposed) throw StateError('设备偏好已关闭');
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _pending.then((_) async {
      _ensureLive();
      await operation();
    });
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> load({required bool hasExistingVault}) => _enqueue(() async {
    var loaded = const DevicePreferences();
    try {
      final data = await repository.read();
      if (data != null) loaded = DevicePreferences.fromJson(data);
    } on Object {
      // A broken preference file must never initiate creation over a vault.
    }
    _ensureLive();
    if (hasExistingVault && !loaded.onboardingStarted) {
      loaded = DevicePreferences(
        appearance: loaded.appearance,
        readingSize: loaded.readingSize,
        language: loaded.language,
        onboardingComplete: true,
      );
    }
    _state = loaded;
    _changes.add(state);
  });
  Future<void> setAppearance({AppearanceMode? mode, ReadingSize? size}) =>
      _save(mode: mode, size: size);
  Future<void> setLanguage(AppLanguage language) =>
      _save(language: language);
  Future<void> beginOnboarding() => _save(started: true);
  Future<void> finishOnboarding() => _save(started: true, complete: true);

  Future<void> _save({
    AppearanceMode? mode,
    ReadingSize? size,
    AppLanguage? language,
    bool? started,
    bool? complete,
  }) => _enqueue(() async {
    final next = DevicePreferences(
      appearance: mode ?? state.appearance,
      readingSize: size ?? state.readingSize,
      language: language ?? state.language,
      onboardingStarted: started ?? state.onboardingStarted,
      onboardingComplete: complete ?? state.onboardingComplete,
    );
    await repository.write(next.toJson());
    _ensureLive();
    _state = next;
    _changes.add(state);
  });
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_changes.close());
  }
}
