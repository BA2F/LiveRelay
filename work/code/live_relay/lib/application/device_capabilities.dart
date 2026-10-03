import 'dart:io';

enum DevicePlatform { android, ios, linux, windows, macos, other }

enum AppFeature {
  camera,
  ocr,
  mediaPlayback,
  documentPreview,
  biometric,
  speechInput,
  agent,
  checkIn,
  partialBackup,
  english,
}

enum CapabilityStatus { available, unsupported, notImplemented, needsSetup }

class FeatureCapability {
  const FeatureCapability(this.status, this.message);
  final CapabilityStatus status;
  final String message;
  bool get isAvailable => status == CapabilityStatus.available;
}

class DeviceCapabilities {
  const DeviceCapabilities(this.platform);
  factory DeviceCapabilities.current() => DeviceCapabilities(
    Platform.isAndroid
        ? DevicePlatform.android
        : Platform.isIOS
        ? DevicePlatform.ios
        : Platform.isLinux
        ? DevicePlatform.linux
        : Platform.isWindows
        ? DevicePlatform.windows
        : Platform.isMacOS
        ? DevicePlatform.macos
        : DevicePlatform.other,
  );
  final DevicePlatform platform;
  bool get isMobile =>
      platform == DevicePlatform.android || platform == DevicePlatform.ios;

  FeatureCapability feature(
    AppFeature feature, {
    bool biometricAvailable = false,
  }) => switch (feature) {
    AppFeature.camera || AppFeature.ocr =>
      isMobile
          ? const FeatureCapability(CapabilityStatus.available, '可用')
          : const FeatureCapability(CapabilityStatus.unsupported, '此设备暂不支持'),
    AppFeature.biometric =>
      platform != DevicePlatform.android
          ? const FeatureCapability(CapabilityStatus.unsupported, '此设备暂不支持')
          : biometricAvailable
          ? const FeatureCapability(CapabilityStatus.available, '可用')
          : const FeatureCapability(
              CapabilityStatus.needsSetup,
              '请先在设备设置中启用生物识别',
            ),
    AppFeature.mediaPlayback =>
      isMobile || platform == DevicePlatform.macos
          ? const FeatureCapability(CapabilityStatus.available, '可用')
          : const FeatureCapability(
              CapabilityStatus.unsupported,
              '此设备暂不支持音视频播放，原件已保留',
            ),
    AppFeature.documentPreview => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '此文件类型暂不支持预览，原件已保留',
    ),
    AppFeature.speechInput => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '语音输入暂未提供，可使用系统输入法',
    ),
    AppFeature.agent => const FeatureCapability(
      CapabilityStatus.notImplemented,
      'Agent 暂未提供',
    ),
    AppFeature.checkIn => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '报平安与自动交接暂未提供',
    ),
    AppFeature.partialBackup => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '拆分备份暂未提供，请使用完整备份',
    ),
    AppFeature.english => const FeatureCapability(
      CapabilityStatus.notImplemented,
      'English is not available yet',
    ),
  };
}
