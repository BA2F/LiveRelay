import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

enum AppearanceMode { system, light, dark }

enum ReadingSize { medium, large }

/// Device preferences contain no vault identity, credentials or authority.
class AppPreferences extends ChangeNotifier {
  AppPreferences([this._file]);
  final File? _file;
  AppearanceMode appearance = AppearanceMode.system;
  ReadingSize readingSize = ReadingSize.medium;
  bool onboardingStarted = false;
  bool onboardingComplete = false;
  String? desktopPreset;
  Future<void> _pending = Future.value();

  Future<void> load({required bool hasExistingVault}) async {
    try {
      if (_file != null && await _file.exists()) {
        final data =
            jsonDecode(await _file.readAsString()) as Map<String, dynamic>;
        if (data['version'] != 1) throw const FormatException('偏好版本不支持');
        appearance = AppearanceMode.values.firstWhere(
          (v) => v.name == data['appearance'],
          orElse: () => AppearanceMode.system,
        );
        readingSize = ReadingSize.values.firstWhere(
          (v) => v.name == data['readingSize'],
          orElse: () => ReadingSize.medium,
        );
        onboardingStarted = data['onboardingStarted'] == true;
        onboardingComplete = data['onboardingComplete'] == true;
        desktopPreset = ['library', 'assistant'].contains(data['desktopPreset'])
            ? data['desktopPreset'] as String
            : null;
      }
    } on Object {
      appearance = AppearanceMode.system;
      readingSize = ReadingSize.medium;
      onboardingStarted = false;
      onboardingComplete = false;
      desktopPreset = null;
    }
    // Legacy vaults and damaged device preferences never trigger vault creation.
    if (hasExistingVault && !onboardingStarted) onboardingComplete = true;
    notifyListeners();
  }

  Future<void> setAppearance({AppearanceMode? mode, ReadingSize? size}) =>
      _save(mode: mode, size: size);
  Future<void> beginOnboarding() => _save(started: true);
  Future<void> finishOnboarding() => _save(started: true, complete: true);
  Future<void> setDesktopPreset(String? preset) =>
      _save(preset: preset, clearPreset: preset == null);

  Future<void> _save({
    AppearanceMode? mode,
    ReadingSize? size,
    bool? started,
    bool? complete,
    String? preset,
    bool clearPreset = false,
  }) {
    final next = _pending.then((_) async {
      final data = <String, Object?>{
        'version': 1,
        'appearance': (mode ?? appearance).name,
        'readingSize': (size ?? readingSize).name,
        'onboardingStarted': started ?? onboardingStarted,
        'onboardingComplete': complete ?? onboardingComplete,
        'desktopPreset': clearPreset ? null : preset ?? desktopPreset,
      };
      final file = _file;
      if (file != null) {
        await file.parent.create(recursive: true);
        final temporary = File('${file.path}.tmp');
        try {
          await temporary.writeAsString(jsonEncode(data), flush: true);
          await temporary.rename(file.path);
        } finally {
          if (await temporary.exists()) await temporary.delete();
        }
      }
      appearance = mode ?? appearance;
      readingSize = size ?? readingSize;
      onboardingStarted = started ?? onboardingStarted;
      onboardingComplete = complete ?? onboardingComplete;
      desktopPreset = clearPreset ? null : preset ?? desktopPreset;
      notifyListeners();
    });
    _pending = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }
}
