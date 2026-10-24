// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'LiveRelay';

  @override
  String get appCannotOpen => 'Can\'t open LiveRelay';

  @override
  String get appInitFailed => 'Setup failed';

  @override
  String get brandName => 'LiveRelay';

  @override
  String get brandTagline => 'Keep what matters where you control it.';

  @override
  String get gateTagline => 'Keep what matters where you control it.';

  @override
  String get back => 'Back';

  @override
  String get done => 'Done';

  @override
  String get cancel => 'Cancel';

  @override
  String get settingsSaveFailed => 'Couldn\'t save. Try again.';

  @override
  String get recoveryTitle => 'Save the recovery credential';

  @override
  String get recoveryWarning =>
      'This credential bypasses daily unlock and can reset the vault security. Keep it offline, separately; if lost it can\'t be recovered for you.';

  @override
  String get recoveryCopy => 'Copy credential';

  @override
  String get recoverySavedCheck => 'I\'ve saved the credential separately';

  @override
  String get recoveryConfirmField => 'Type the credential in full to confirm';

  @override
  String get recoveryConfirmed => 'Confirmed, continue';

  @override
  String get onboardingWelcome => 'Welcome to LiveRelay';

  @override
  String onboardingStep(int current) {
    return 'Setup $current / 3';
  }

  @override
  String get onboardingChooseLanguage => 'Choose a language';

  @override
  String get onboardingYourVault => 'Your vault';

  @override
  String get onboardingCreate => 'Create a vault';

  @override
  String get onboardingRestore => 'Restore from a backup';

  @override
  String get onboardingContinue => 'Continue';

  @override
  String get onboardingSaveFailed => 'Couldn\'t save settings. Try again.';

  @override
  String get finishReady => 'Ready';

  @override
  String get finishMessage =>
      'Your vault lives on this device. Keep an encrypted backup off the device too, and keep the passphrase safe.';

  @override
  String get finishStart => 'Start using';

  @override
  String get appearanceTitle => 'Appearance';

  @override
  String get appearanceSystem => 'System';

  @override
  String get appearanceLight => 'Light';

  @override
  String get appearanceDark => 'Dark';

  @override
  String get readingSizeTitle => 'Text size';

  @override
  String get readingSizeMedium => 'Medium (default)';

  @override
  String get readingSizeLarge => 'Large';

  @override
  String get setupTitle => 'Create your encrypted vault';

  @override
  String get setupIntro =>
      'Write down where things are kept, accounts, assets, or anything you want to pass on. Everything stays encrypted on this device and is visible only to you by default. Export an encrypted backup regularly; if the device is lost you can restore with your passphrase.';

  @override
  String get setupRestore => 'Have an encrypted backup? Restore it';

  @override
  String get setupImportMedium =>
      'Import from a medium (device transfer, replaces the vault)';

  @override
  String get setupChipCustom => 'Custom password';

  @override
  String get setupChipPhrase => 'Chinese phrase';

  @override
  String get setupPhraseHint =>
      'Six random words by default; unlock with hanzi or pinyin.';

  @override
  String get setupAdvancedLength => 'Advanced: passphrase length';

  @override
  String get setupWordCountLabel => 'Words';

  @override
  String setupWordCountValue(int count) {
    return '$count';
  }

  @override
  String get setupGenerate => 'Generate a passphrase';

  @override
  String get setupPhraseLabel => 'Passphrase';

  @override
  String get setupPhraseHelperEmpty => 'Tap the button above to generate';

  @override
  String get setupPhraseHelperGenerated => 'Generated';

  @override
  String get setupPasswordLabel => 'Master password';

  @override
  String setupPasswordHelper(int count) {
    return 'At least $count characters. Chinese, letters, digits or symbols are all fine.';
  }

  @override
  String get setupShow => 'Show';

  @override
  String get setupHide => 'Hide';

  @override
  String get setupLengthOk => 'Password length is fine';

  @override
  String get passwordStrengthWeak => 'Weak';

  @override
  String get passwordStrengthMedium => 'Medium';

  @override
  String get passwordStrengthStrong => 'Strong';

  @override
  String get setupConfirmLabel => 'Enter the master password again';

  @override
  String get setupMismatch => 'The two entries don\'t match';

  @override
  String get setupConfirmOk => 'Both entries match';

  @override
  String get setupSavedCheck => 'I\'ve saved the passphrase safely';

  @override
  String get setupSavedSubtitle =>
      'It can\'t be recovered. You\'ll need it to unlock on a new device.';

  @override
  String get setupBiometric => 'Enable fingerprint unlock';

  @override
  String get setupBiometricSubtitle =>
      'Fingerprint unlock works on this device only';

  @override
  String get setupSubmit => 'Create and open the vault';

  @override
  String get setupSaveFirst => 'Confirm you\'ve saved the passphrase first';

  @override
  String get setupGenerateFirst => 'Generate the phrase first';

  @override
  String get setupCreateFailed => 'The vault wasn\'t created. Try again.';

  @override
  String get unlockTitle => 'Unlock your encrypted vault';

  @override
  String get unlockFieldPhrase => 'Chinese phrase or pinyin';

  @override
  String get unlockButton => 'Unlock';

  @override
  String get unlockRestore => 'Restore from an encrypted backup';

  @override
  String get unlockKeyFile => 'Unlock with a key file';

  @override
  String get unlockRecovery =>
      'Forgot the password? Use the recovery credential';

  @override
  String get unlockBiometric => 'Unlock with fingerprint';

  @override
  String get recipientEntry => 'I\'m a recipient · Open the read-only vault';

  @override
  String get recipientCreate => 'Create a recipient identity';

  @override
  String get tabRecord => 'Record';

  @override
  String get tabCards => 'Cards';

  @override
  String get tabPasswords => 'Passwords';

  @override
  String get tabHandoff => 'Handoff';

  @override
  String get tabProfile => 'Me';

  @override
  String get shellHandoffTitle => 'Handoff';

  @override
  String get shellSettings => 'Settings';

  @override
  String get shellLock => 'Lock the vault';

  @override
  String get shellNewCard => 'New card';

  @override
  String get shellNewCardInfo => 'Info card';

  @override
  String get shellNewCardPassword => 'Password card';

  @override
  String get captureTitle => 'Write it down';

  @override
  String get captureSubtitle => 'Organize it later.';

  @override
  String get captureNewCard => 'Add a note';

  @override
  String get captureCamera => 'Photo';

  @override
  String get captureRecordAudio => 'Voice note';

  @override
  String get captureAgent => 'Tidy with Agent';

  @override
  String get captureMore => 'More';

  @override
  String captureDraftTile(int count) {
    return 'To review · $count';
  }

  @override
  String get captureDraftTitle => 'To review';

  @override
  String get captureDraftSubtitle =>
      'Check drafts, add details, then confirm them yourself';

  @override
  String get captureRecent => 'Recent';

  @override
  String get captureRecentSubtitle => 'Encrypted on this device · by last edit';

  @override
  String get captureEmptyTitle => 'Nothing yet';

  @override
  String get captureEmptyMessage => 'What you write shows up here.';

  @override
  String captureAllOriginals(int count) {
    return 'All files · $count';
  }

  @override
  String captureStale(int count) {
    return '$count cards not confirmed in over six months';
  }

  @override
  String get captureStaleSubtitle =>
      'Open them to check; sources and history are kept.';

  @override
  String get captureImportPhoto => 'Import photo';

  @override
  String get captureImportAudio => 'Import audio';

  @override
  String get captureImportVideo => 'Import video';

  @override
  String get captureRecordVideo => 'Record video';

  @override
  String get captureVideo => 'Video';

  @override
  String get captureSavedOriginal =>
      'File saved and encrypted; a source card was created';

  @override
  String get captureImportFailed => 'Import failed';

  @override
  String get captureSavedCapture =>
      'Capture saved and encrypted; a source card was created';

  @override
  String get captureCaptureFailed => 'Capture failed';

  @override
  String get captureSavedRecording =>
      'Recording saved and encrypted; a source card was created';

  @override
  String get captureTranscribe => 'Transcribe';

  @override
  String get captureRecordFailed => 'Couldn\'t save the recording';

  @override
  String get recorderTitle => 'Record a voice note';

  @override
  String get recorderHint =>
      'The recording is encrypted, up to 60 seconds. You can transcribe it after saving.';

  @override
  String get recorderCancel => 'Cancel';

  @override
  String get recorderStop => 'Stop and save';

  @override
  String get recorderStart => 'Start recording';

  @override
  String get recorderNoPermission => 'Microphone permission was not granted';

  @override
  String get languageTitle => 'Language';
}
