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
    bool agentConfigured = false,
    bool speechInstalled = false,
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
      isMobile ||
              platform == DevicePlatform.macos ||
              platform == DevicePlatform.linux
          ? const FeatureCapability(CapabilityStatus.available, '可用')
          : const FeatureCapability(
              CapabilityStatus.unsupported,
              '此设备暂不支持音视频播放，原件已保留',
            ),
    AppFeature.documentPreview => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '此文件类型暂不支持预览，原件已保留',
    ),
    AppFeature.speechInput =>
      !{
            DevicePlatform.android,
            DevicePlatform.linux,
            DevicePlatform.windows,
          }.contains(platform)
          ? const FeatureCapability(CapabilityStatus.unsupported, '此平台尚未支持本地语音')
          : speechInstalled
          ? const FeatureCapability(CapabilityStatus.available, '本地模型已安装')
          : const FeatureCapability(CapabilityStatus.needsSetup, '请先安装本地语音模型'),
    AppFeature.agent =>
      agentConfigured
          ? const FeatureCapability(
              CapabilityStatus.available,
              '可整理本次选中内容，生成待核对草稿',
            )
          : const FeatureCapability(
              CapabilityStatus.needsSetup,
              '请配置 Responses AI 服务',
            ),
    AppFeature.checkIn => const FeatureCapability(
      CapabilityStatus.notImplemented,
      '报平安与自动交接暂未提供',
    ),
    AppFeature.partialBackup => const FeatureCapability(
      CapabilityStatus.available,
      '本地数据库包与原件补充包（需安全格式 v3）',
    ),
    AppFeature.english => const FeatureCapability(
      CapabilityStatus.notImplemented,
      'English is not available yet',
    ),
  };
}
