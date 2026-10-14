// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => '留灯 LiveRelay';

  @override
  String get appCannotOpen => '无法打开留灯';

  @override
  String get appInitFailed => '初始化失败';

  @override
  String get brandName => '留灯';

  @override
  String get brandTagline => '把重要信息留在你能掌控的地方。';

  @override
  String get gateTagline => 'LiveRelay · 把重要信息留在你能掌控的地方';

  @override
  String get back => '返回';

  @override
  String get done => '完成';

  @override
  String get cancel => '取消';

  @override
  String get settingsSaveFailed => '设置未保存，请重试';

  @override
  String get recoveryTitle => '保存独立恢复凭证';

  @override
  String get recoveryWarning => '此凭证可以绕过日常解锁条件并重设整库安全设置。请单独离线保存；丢失后无法代为找回。';

  @override
  String get recoveryCopy => '复制恢复凭证';

  @override
  String get recoverySavedCheck => '我已单独保存恢复凭证';

  @override
  String get recoveryConfirmField => '完整回输凭证确认';

  @override
  String get recoveryConfirmed => '已确认，继续';

  @override
  String get onboardingWelcome => '欢迎使用留灯';

  @override
  String onboardingStep(int current) {
    return '设置 $current / 3';
  }

  @override
  String get onboardingChooseLanguage => '选择语言';

  @override
  String get onboardingYourVault => '你的资料库';

  @override
  String get onboardingCreate => '创建资料库';

  @override
  String get onboardingRestore => '恢复已有资料库';

  @override
  String get onboardingContinue => '继续';

  @override
  String get onboardingSaveFailed => '无法保存设置，请重试';

  @override
  String get finishReady => '准备好了';

  @override
  String get finishMessage => '资料保存在本机。记得把加密备份另存到设备外，并妥善保存解锁口令。';

  @override
  String get finishStart => '开始使用';

  @override
  String get appearanceTitle => '外观';

  @override
  String get appearanceSystem => '跟随系统';

  @override
  String get appearanceLight => '浅色';

  @override
  String get appearanceDark => '深色';

  @override
  String get readingSizeTitle => '文字大小';

  @override
  String get readingSizeMedium => '中等（默认）';

  @override
  String get readingSizeLarge => '大';

  @override
  String get setupTitle => '创建你的加密资料库';

  @override
  String get setupIntro =>
      '记下资料位置、账号、资产或想交代的事。内容加密保存在本机，默认只有本人可见。请定期导出加密备份，设备丢失后可用口令恢复。';

  @override
  String get setupRestore => '已有加密备份？从备份恢复';

  @override
  String get setupImportMedium => '从介质导入（设备间搬运，整库替换）';

  @override
  String get setupChipCustom => '自定密码';

  @override
  String get setupChipPhrase => '中文词组';

  @override
  String get setupPhraseHint => '默认使用 6 个随机词组；汉字或拼音均可解锁。';

  @override
  String get setupAdvancedLength => '高级：口令长度';

  @override
  String get setupWordCountLabel => '词数';

  @override
  String setupWordCountValue(int count) {
    return '$count 个';
  }

  @override
  String get setupGenerate => '安全生成一组口令';

  @override
  String get setupPhraseLabel => '中文词组口令';

  @override
  String get setupPhraseHelperEmpty => '点击上方按钮生成口令';

  @override
  String get setupPhraseHelperGenerated => '已生成';

  @override
  String get setupPasswordLabel => '主密码';

  @override
  String setupPasswordHelper(int count) {
    return '至少 $count 个字符，支持中文、字母、数字和符号';
  }

  @override
  String get setupShow => '显示口令';

  @override
  String get setupHide => '遮挡口令';

  @override
  String get setupLengthOk => '密码长度符合要求';

  @override
  String get setupConfirmLabel => '再次输入主密码';

  @override
  String get setupMismatch => '两次输入的密码不一致';

  @override
  String get setupConfirmOk => '两次输入一致';

  @override
  String get setupSavedCheck => '我已妥善保存口令';

  @override
  String get setupSavedSubtitle => '口令无法找回。换设备后需要口令才能解锁。';

  @override
  String get setupBiometric => '启用指纹解锁';

  @override
  String get setupBiometricSubtitle => '指纹解锁只对这台设备有效';

  @override
  String get setupSubmit => '创建并进入资料库';

  @override
  String get setupSaveFirst => '请先确认已妥善保存口令';

  @override
  String get setupGenerateFirst => '请先生成中文词组口令';

  @override
  String get setupCreateFailed => '资料库未创建，请重试';

  @override
  String get unlockTitle => '解锁你的加密资料库';

  @override
  String get unlockFieldPhrase => '中文词组或拼音';

  @override
  String get unlockButton => '解锁';

  @override
  String get unlockRestore => '从加密备份恢复';

  @override
  String get unlockKeyFile => '使用密钥文件解锁';

  @override
  String get unlockRecovery => '忘记密码？使用独立恢复凭证';

  @override
  String get unlockBiometric => '使用指纹解锁';

  @override
  String get recipientEntry => '我是接收者 · 打开独立只读资料库';

  @override
  String get tabRecord => '记录';

  @override
  String get tabCards => '卡片';

  @override
  String get tabPasswords => '密码库';

  @override
  String get tabHandoff => '交接';

  @override
  String get tabProfile => '我的';

  @override
  String get shellHandoffTitle => '交接准备';

  @override
  String get shellSettings => '设置';

  @override
  String get shellLock => '锁定加密资料库';

  @override
  String get shellNewCard => '新建卡片';

  @override
  String get shellNewCardInfo => '信息卡片';

  @override
  String get shellNewCardPassword => '密码卡片';

  @override
  String get captureTitle => '先记下来';

  @override
  String get captureSubtitle => '重要的事，之后再慢慢整理。';

  @override
  String get captureNewCard => '记一条';

  @override
  String get captureCamera => '拍照';

  @override
  String get captureRecordAudio => '录音';

  @override
  String get captureAgent => 'Agent 整理';

  @override
  String get captureMore => '更多';

  @override
  String captureDraftTile(int count) {
    return '待整理 · $count 条';
  }

  @override
  String get captureDraftTitle => '待整理';

  @override
  String get captureDraftSubtitle => '核对草稿、补充信息，再由本人确认';

  @override
  String get captureRecent => '最近记录';

  @override
  String get captureRecentSubtitle => '已加密保存在本机 · 按最近修改排序';

  @override
  String get captureEmptyTitle => '还没有记录';

  @override
  String get captureEmptyMessage => '记下的内容会出现在这里。';

  @override
  String captureAllOriginals(int count) {
    return '全部原件 · $count 个';
  }

  @override
  String captureStale(int count) {
    return '$count 张卡片超过半年未确认';
  }

  @override
  String get captureStaleSubtitle => '打开卡片核对，旧来源和历史会保留。';

  @override
  String get captureImportPhoto => '导入照片';

  @override
  String get captureImportAudio => '导入录音';

  @override
  String get captureImportVideo => '导入录像';

  @override
  String get captureRecordVideo => '现场录像';

  @override
  String get captureVideo => '录像';

  @override
  String get captureSavedOriginal => '原始资料已加密保存，并建立来源卡片';

  @override
  String get captureImportFailed => '导入失败';

  @override
  String get captureSavedCapture => '现场采集已加密保存，并建立来源卡片';

  @override
  String get captureCaptureFailed => '采集失败';

  @override
  String get captureSavedRecording => '录音已加密保存，并建立来源卡片';

  @override
  String get captureTranscribe => '转写为文字';

  @override
  String get captureRecordFailed => '录音保存失败';

  @override
  String get recorderTitle => '录制一段原始语音';

  @override
  String get recorderHint => '录音会加密保存，最长 60 秒；保存后可转写为文字。';

  @override
  String get recorderCancel => '取消';

  @override
  String get recorderStop => '停止并保存';

  @override
  String get recorderStart => '开始录音';

  @override
  String get recorderNoPermission => '未获得麦克风权限';

  @override
  String get languageTitle => '语言';
}
