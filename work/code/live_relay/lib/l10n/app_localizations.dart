import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'留灯 LiveRelay'**
  String get appTitle;

  /// No description provided for @appCannotOpen.
  ///
  /// In zh, this message translates to:
  /// **'无法打开留灯'**
  String get appCannotOpen;

  /// No description provided for @appInitFailed.
  ///
  /// In zh, this message translates to:
  /// **'初始化失败'**
  String get appInitFailed;

  /// No description provided for @brandName.
  ///
  /// In zh, this message translates to:
  /// **'留灯'**
  String get brandName;

  /// No description provided for @brandTagline.
  ///
  /// In zh, this message translates to:
  /// **'把重要信息留在你能掌控的地方。'**
  String get brandTagline;

  /// No description provided for @gateTagline.
  ///
  /// In zh, this message translates to:
  /// **'LiveRelay · 把重要信息留在你能掌控的地方'**
  String get gateTagline;

  /// No description provided for @back.
  ///
  /// In zh, this message translates to:
  /// **'返回'**
  String get back;

  /// No description provided for @done.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get done;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @settingsSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'设置未保存，请重试'**
  String get settingsSaveFailed;

  /// No description provided for @recoveryTitle.
  ///
  /// In zh, this message translates to:
  /// **'保存独立恢复凭证'**
  String get recoveryTitle;

  /// No description provided for @recoveryWarning.
  ///
  /// In zh, this message translates to:
  /// **'此凭证可以绕过日常解锁条件并重设整库安全设置。请单独离线保存；丢失后无法代为找回。'**
  String get recoveryWarning;

  /// No description provided for @recoveryCopy.
  ///
  /// In zh, this message translates to:
  /// **'复制恢复凭证'**
  String get recoveryCopy;

  /// No description provided for @recoverySavedCheck.
  ///
  /// In zh, this message translates to:
  /// **'我已单独保存恢复凭证'**
  String get recoverySavedCheck;

  /// No description provided for @recoveryConfirmField.
  ///
  /// In zh, this message translates to:
  /// **'完整回输凭证确认'**
  String get recoveryConfirmField;

  /// No description provided for @recoveryConfirmed.
  ///
  /// In zh, this message translates to:
  /// **'已确认，继续'**
  String get recoveryConfirmed;

  /// No description provided for @onboardingWelcome.
  ///
  /// In zh, this message translates to:
  /// **'欢迎使用留灯'**
  String get onboardingWelcome;

  /// No description provided for @onboardingStep.
  ///
  /// In zh, this message translates to:
  /// **'设置 {current} / 3'**
  String onboardingStep(int current);

  /// No description provided for @onboardingChooseLanguage.
  ///
  /// In zh, this message translates to:
  /// **'选择语言'**
  String get onboardingChooseLanguage;

  /// No description provided for @onboardingYourVault.
  ///
  /// In zh, this message translates to:
  /// **'你的资料库'**
  String get onboardingYourVault;

  /// No description provided for @onboardingCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建资料库'**
  String get onboardingCreate;

  /// No description provided for @onboardingRestore.
  ///
  /// In zh, this message translates to:
  /// **'恢复已有资料库'**
  String get onboardingRestore;

  /// No description provided for @onboardingContinue.
  ///
  /// In zh, this message translates to:
  /// **'继续'**
  String get onboardingContinue;

  /// No description provided for @onboardingSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'无法保存设置，请重试'**
  String get onboardingSaveFailed;

  /// No description provided for @finishReady.
  ///
  /// In zh, this message translates to:
  /// **'准备好了'**
  String get finishReady;

  /// No description provided for @finishMessage.
  ///
  /// In zh, this message translates to:
  /// **'资料保存在本机。记得把加密备份另存到设备外，并妥善保存解锁口令。'**
  String get finishMessage;

  /// No description provided for @finishStart.
  ///
  /// In zh, this message translates to:
  /// **'开始使用'**
  String get finishStart;

  /// No description provided for @appearanceTitle.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get appearanceTitle;

  /// No description provided for @appearanceSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get appearanceSystem;

  /// No description provided for @appearanceLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get appearanceLight;

  /// No description provided for @appearanceDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get appearanceDark;

  /// No description provided for @readingSizeTitle.
  ///
  /// In zh, this message translates to:
  /// **'文字大小'**
  String get readingSizeTitle;

  /// No description provided for @readingSizeMedium.
  ///
  /// In zh, this message translates to:
  /// **'中等（默认）'**
  String get readingSizeMedium;

  /// No description provided for @readingSizeLarge.
  ///
  /// In zh, this message translates to:
  /// **'大'**
  String get readingSizeLarge;

  /// No description provided for @setupTitle.
  ///
  /// In zh, this message translates to:
  /// **'创建你的加密资料库'**
  String get setupTitle;

  /// No description provided for @setupIntro.
  ///
  /// In zh, this message translates to:
  /// **'记下资料位置、账号、资产或想交代的事。内容加密保存在本机，默认只有本人可见。请定期导出加密备份，设备丢失后可用口令恢复。'**
  String get setupIntro;

  /// No description provided for @setupRestore.
  ///
  /// In zh, this message translates to:
  /// **'已有加密备份？从备份恢复'**
  String get setupRestore;

  /// No description provided for @setupImportMedium.
  ///
  /// In zh, this message translates to:
  /// **'从介质导入（设备间搬运，整库替换）'**
  String get setupImportMedium;

  /// No description provided for @setupChipCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定密码'**
  String get setupChipCustom;

  /// No description provided for @setupChipPhrase.
  ///
  /// In zh, this message translates to:
  /// **'中文词组'**
  String get setupChipPhrase;

  /// No description provided for @setupPhraseHint.
  ///
  /// In zh, this message translates to:
  /// **'默认使用 6 个随机词组；汉字或拼音均可解锁。'**
  String get setupPhraseHint;

  /// No description provided for @setupAdvancedLength.
  ///
  /// In zh, this message translates to:
  /// **'高级：口令长度'**
  String get setupAdvancedLength;

  /// No description provided for @setupWordCountLabel.
  ///
  /// In zh, this message translates to:
  /// **'词数'**
  String get setupWordCountLabel;

  /// No description provided for @setupWordCountValue.
  ///
  /// In zh, this message translates to:
  /// **'{count} 个'**
  String setupWordCountValue(int count);

  /// No description provided for @setupGenerate.
  ///
  /// In zh, this message translates to:
  /// **'安全生成一组口令'**
  String get setupGenerate;

  /// No description provided for @setupPhraseLabel.
  ///
  /// In zh, this message translates to:
  /// **'中文词组口令'**
  String get setupPhraseLabel;

  /// No description provided for @setupPhraseHelperEmpty.
  ///
  /// In zh, this message translates to:
  /// **'点击上方按钮生成口令'**
  String get setupPhraseHelperEmpty;

  /// No description provided for @setupPhraseHelperGenerated.
  ///
  /// In zh, this message translates to:
  /// **'已生成'**
  String get setupPhraseHelperGenerated;

  /// No description provided for @setupPasswordLabel.
  ///
  /// In zh, this message translates to:
  /// **'主密码'**
  String get setupPasswordLabel;

  /// No description provided for @setupPasswordHelper.
  ///
  /// In zh, this message translates to:
  /// **'至少 {count} 个字符，支持中文、字母、数字和符号'**
  String setupPasswordHelper(int count);

  /// No description provided for @setupShow.
  ///
  /// In zh, this message translates to:
  /// **'显示口令'**
  String get setupShow;

  /// No description provided for @setupHide.
  ///
  /// In zh, this message translates to:
  /// **'遮挡口令'**
  String get setupHide;

  /// No description provided for @setupLengthOk.
  ///
  /// In zh, this message translates to:
  /// **'密码长度符合要求'**
  String get setupLengthOk;

  /// No description provided for @passwordStrengthWeak.
  ///
  /// In zh, this message translates to:
  /// **'弱'**
  String get passwordStrengthWeak;

  /// No description provided for @passwordStrengthMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get passwordStrengthMedium;

  /// No description provided for @passwordStrengthStrong.
  ///
  /// In zh, this message translates to:
  /// **'强'**
  String get passwordStrengthStrong;

  /// No description provided for @setupConfirmLabel.
  ///
  /// In zh, this message translates to:
  /// **'再次输入主密码'**
  String get setupConfirmLabel;

  /// No description provided for @setupMismatch.
  ///
  /// In zh, this message translates to:
  /// **'两次输入的密码不一致'**
  String get setupMismatch;

  /// No description provided for @setupConfirmOk.
  ///
  /// In zh, this message translates to:
  /// **'两次输入一致'**
  String get setupConfirmOk;

  /// No description provided for @setupSavedCheck.
  ///
  /// In zh, this message translates to:
  /// **'我已妥善保存口令'**
  String get setupSavedCheck;

  /// No description provided for @setupSavedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'口令无法找回。换设备后需要口令才能解锁。'**
  String get setupSavedSubtitle;

  /// No description provided for @setupBiometric.
  ///
  /// In zh, this message translates to:
  /// **'启用指纹解锁'**
  String get setupBiometric;

  /// No description provided for @setupBiometricSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'指纹解锁只对这台设备有效'**
  String get setupBiometricSubtitle;

  /// No description provided for @setupSubmit.
  ///
  /// In zh, this message translates to:
  /// **'创建并进入资料库'**
  String get setupSubmit;

  /// No description provided for @setupSaveFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先确认已妥善保存口令'**
  String get setupSaveFirst;

  /// No description provided for @setupGenerateFirst.
  ///
  /// In zh, this message translates to:
  /// **'请先生成中文词组口令'**
  String get setupGenerateFirst;

  /// No description provided for @setupCreateFailed.
  ///
  /// In zh, this message translates to:
  /// **'资料库未创建，请重试'**
  String get setupCreateFailed;

  /// No description provided for @unlockTitle.
  ///
  /// In zh, this message translates to:
  /// **'解锁你的加密资料库'**
  String get unlockTitle;

  /// No description provided for @unlockFieldPhrase.
  ///
  /// In zh, this message translates to:
  /// **'中文词组或拼音'**
  String get unlockFieldPhrase;

  /// No description provided for @unlockButton.
  ///
  /// In zh, this message translates to:
  /// **'解锁'**
  String get unlockButton;

  /// No description provided for @unlockRestore.
  ///
  /// In zh, this message translates to:
  /// **'从加密备份恢复'**
  String get unlockRestore;

  /// No description provided for @unlockKeyFile.
  ///
  /// In zh, this message translates to:
  /// **'使用密钥文件解锁'**
  String get unlockKeyFile;

  /// No description provided for @unlockRecovery.
  ///
  /// In zh, this message translates to:
  /// **'忘记密码？使用独立恢复凭证'**
  String get unlockRecovery;

  /// No description provided for @unlockBiometric.
  ///
  /// In zh, this message translates to:
  /// **'使用指纹解锁'**
  String get unlockBiometric;

  /// No description provided for @recipientEntry.
  ///
  /// In zh, this message translates to:
  /// **'我是接收者 · 打开独立只读资料库'**
  String get recipientEntry;

  /// No description provided for @recipientCreate.
  ///
  /// In zh, this message translates to:
  /// **'创建接收者身份'**
  String get recipientCreate;

  /// No description provided for @tabRecord.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get tabRecord;

  /// No description provided for @tabCards.
  ///
  /// In zh, this message translates to:
  /// **'卡片'**
  String get tabCards;

  /// No description provided for @tabPasswords.
  ///
  /// In zh, this message translates to:
  /// **'密码库'**
  String get tabPasswords;

  /// No description provided for @tabHandoff.
  ///
  /// In zh, this message translates to:
  /// **'交接'**
  String get tabHandoff;

  /// No description provided for @tabProfile.
  ///
  /// In zh, this message translates to:
  /// **'我的'**
  String get tabProfile;

  /// No description provided for @shellHandoffTitle.
  ///
  /// In zh, this message translates to:
  /// **'交接准备'**
  String get shellHandoffTitle;

  /// No description provided for @shellSettings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get shellSettings;

  /// No description provided for @shellLock.
  ///
  /// In zh, this message translates to:
  /// **'锁定加密资料库'**
  String get shellLock;

  /// No description provided for @shellNewCard.
  ///
  /// In zh, this message translates to:
  /// **'新建卡片'**
  String get shellNewCard;

  /// No description provided for @shellNewCardInfo.
  ///
  /// In zh, this message translates to:
  /// **'信息卡片'**
  String get shellNewCardInfo;

  /// No description provided for @shellNewCardPassword.
  ///
  /// In zh, this message translates to:
  /// **'密码卡片'**
  String get shellNewCardPassword;

  /// No description provided for @captureTitle.
  ///
  /// In zh, this message translates to:
  /// **'先记下来'**
  String get captureTitle;

  /// No description provided for @captureSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'重要的事，之后再慢慢整理。'**
  String get captureSubtitle;

  /// No description provided for @captureNewCard.
  ///
  /// In zh, this message translates to:
  /// **'记一条'**
  String get captureNewCard;

  /// No description provided for @captureCamera.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get captureCamera;

  /// No description provided for @captureRecordAudio.
  ///
  /// In zh, this message translates to:
  /// **'录音'**
  String get captureRecordAudio;

  /// No description provided for @captureAgent.
  ///
  /// In zh, this message translates to:
  /// **'Agent 整理'**
  String get captureAgent;

  /// No description provided for @captureMore.
  ///
  /// In zh, this message translates to:
  /// **'更多'**
  String get captureMore;

  /// No description provided for @captureDraftTile.
  ///
  /// In zh, this message translates to:
  /// **'待整理 · {count} 条'**
  String captureDraftTile(int count);

  /// No description provided for @captureDraftTitle.
  ///
  /// In zh, this message translates to:
  /// **'待整理'**
  String get captureDraftTitle;

  /// No description provided for @captureDraftSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'核对草稿、补充信息，再由本人确认'**
  String get captureDraftSubtitle;

  /// No description provided for @captureRecent.
  ///
  /// In zh, this message translates to:
  /// **'最近记录'**
  String get captureRecent;

  /// No description provided for @captureRecentSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'已加密保存在本机 · 按最近修改排序'**
  String get captureRecentSubtitle;

  /// No description provided for @captureEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有记录'**
  String get captureEmptyTitle;

  /// No description provided for @captureEmptyMessage.
  ///
  /// In zh, this message translates to:
  /// **'记下的内容会出现在这里。'**
  String get captureEmptyMessage;

  /// No description provided for @captureAllOriginals.
  ///
  /// In zh, this message translates to:
  /// **'全部原件 · {count} 个'**
  String captureAllOriginals(int count);

  /// No description provided for @captureStale.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张卡片超过半年未确认'**
  String captureStale(int count);

  /// No description provided for @captureStaleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'打开卡片核对，旧来源和历史会保留。'**
  String get captureStaleSubtitle;

  /// No description provided for @captureImportPhoto.
  ///
  /// In zh, this message translates to:
  /// **'导入照片'**
  String get captureImportPhoto;

  /// No description provided for @captureImportAudio.
  ///
  /// In zh, this message translates to:
  /// **'导入录音'**
  String get captureImportAudio;

  /// No description provided for @captureImportVideo.
  ///
  /// In zh, this message translates to:
  /// **'导入录像'**
  String get captureImportVideo;

  /// No description provided for @captureRecordVideo.
  ///
  /// In zh, this message translates to:
  /// **'现场录像'**
  String get captureRecordVideo;

  /// No description provided for @captureVideo.
  ///
  /// In zh, this message translates to:
  /// **'录像'**
  String get captureVideo;

  /// No description provided for @captureSavedOriginal.
  ///
  /// In zh, this message translates to:
  /// **'原始资料已加密保存，并建立来源卡片'**
  String get captureSavedOriginal;

  /// No description provided for @captureImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败'**
  String get captureImportFailed;

  /// No description provided for @captureSavedCapture.
  ///
  /// In zh, this message translates to:
  /// **'现场采集已加密保存，并建立来源卡片'**
  String get captureSavedCapture;

  /// No description provided for @captureCaptureFailed.
  ///
  /// In zh, this message translates to:
  /// **'采集失败'**
  String get captureCaptureFailed;

  /// No description provided for @captureSavedRecording.
  ///
  /// In zh, this message translates to:
  /// **'录音已加密保存，并建立来源卡片'**
  String get captureSavedRecording;

  /// No description provided for @captureTranscribe.
  ///
  /// In zh, this message translates to:
  /// **'转写为文字'**
  String get captureTranscribe;

  /// No description provided for @captureRecordFailed.
  ///
  /// In zh, this message translates to:
  /// **'录音保存失败'**
  String get captureRecordFailed;

  /// No description provided for @recorderTitle.
  ///
  /// In zh, this message translates to:
  /// **'录制一段原始语音'**
  String get recorderTitle;

  /// No description provided for @recorderHint.
  ///
  /// In zh, this message translates to:
  /// **'录音会加密保存，最长 60 秒；保存后可转写为文字。'**
  String get recorderHint;

  /// No description provided for @recorderCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get recorderCancel;

  /// No description provided for @recorderStop.
  ///
  /// In zh, this message translates to:
  /// **'停止并保存'**
  String get recorderStop;

  /// No description provided for @recorderStart.
  ///
  /// In zh, this message translates to:
  /// **'开始录音'**
  String get recorderStart;

  /// No description provided for @recorderNoPermission.
  ///
  /// In zh, this message translates to:
  /// **'未获得麦克风权限'**
  String get recorderNoPermission;

  /// No description provided for @languageTitle.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get languageTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
