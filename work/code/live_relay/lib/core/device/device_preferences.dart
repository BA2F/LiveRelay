enum AppearanceMode { system, light, dark }

enum ReadingSize { medium, large }

/// Device-only presentation choices; no vault identity or authority.
class DevicePreferences {
  const DevicePreferences({
    this.appearance = AppearanceMode.system,
    this.readingSize = ReadingSize.medium,
    this.onboardingStarted = false,
    this.onboardingComplete = false,
  });
  final AppearanceMode appearance;
  final ReadingSize readingSize;
  final bool onboardingStarted, onboardingComplete;
  factory DevicePreferences.fromJson(Map<String, Object?> data) {
    if (data['version'] != 1) throw const FormatException('偏好版本不支持');
    return DevicePreferences(
      appearance: AppearanceMode.values.firstWhere(
        (v) => v.name == data['appearance'],
        orElse: () => AppearanceMode.system,
      ),
      readingSize: ReadingSize.values.firstWhere(
        (v) => v.name == data['readingSize'],
        orElse: () => ReadingSize.medium,
      ),
      onboardingStarted: data['onboardingStarted'] == true,
      onboardingComplete: data['onboardingComplete'] == true,
    );
  }
  Map<String, Object?> toJson() => {
    'version': 1,
    'appearance': appearance.name,
    'readingSize': readingSize.name,
    'onboardingStarted': onboardingStarted,
    'onboardingComplete': onboardingComplete,
  };
}
