enum AppearanceMode { system, light, dark }

enum ReadingSize { medium, large }

/// 界面语言。语言试点批次只覆盖引导、建库/解锁与主外壳；其余页面在
/// 英语下仍显示中文。
enum AppLanguage { zh, en }

/// Device-only presentation choices; no vault identity or authority.
class DevicePreferences {
  const DevicePreferences({
    this.appearance = AppearanceMode.system,
    this.readingSize = ReadingSize.medium,
    this.language = AppLanguage.zh,
    this.onboardingStarted = false,
    this.onboardingComplete = false,
  });
  final AppearanceMode appearance;
  final ReadingSize readingSize;
  final AppLanguage language;
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
      language: AppLanguage.values.firstWhere(
        (v) => v.name == data['language'],
        orElse: () => AppLanguage.zh,
      ),
      onboardingStarted: data['onboardingStarted'] == true,
      onboardingComplete: data['onboardingComplete'] == true,
    );
  }
  Map<String, Object?> toJson() => {
    'version': 1,
    'appearance': appearance.name,
    'readingSize': readingSize.name,
    'language': language.name,
    'onboardingStarted': onboardingStarted,
    'onboardingComplete': onboardingComplete,
  };
}
