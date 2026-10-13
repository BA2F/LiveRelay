import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../application/app_controller.dart';
import '../core/device/device_capabilities.dart';
import '../application/device_preferences_runtime.dart';
import '../presentation/controllers/app_preferences.dart';
import 'persistence/file_device_preferences_repository.dart';
import '../application/agent/agent_settings_service.dart';
import '../application/agent/agent_service.dart';
import '../application/ai/outbound_consent_service.dart';
import '../core/ports/outbound_consent_repository.dart';
import 'ai/outbound_consent_store.dart';
import '../application/agent/agent_review_service.dart';
import '../application/agent/conversation_application.dart';
import '../core/ports/ai_settings_repository.dart';
import '../application/vault_backup_service.dart';
import '../application/device_transfer_service.dart';
import '../application/vault_session.dart';
import '../application/vault_snapshot_query.dart';
import '../application/vault_content_service.dart';
import '../application/vault_records_application.dart';
import '../application/vault_security_service.dart';
import '../application/local_handoff_service.dart';
import '../presentation/controllers/recipient_service.dart';
import '../application/identity/recipient_runtime.dart';
import 'identity/file_recipient_store.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/biometric_key_store.dart';
import '../core/ports/device_factor_protection.dart';
import '../core/ports/ocr_provider.dart';
import '../core/security/chinese_passphrase.dart';
import 'ai/ai_provider_settings_store.dart';
import 'private_cache.dart';
import 'ai/configured_ai_provider.dart';
import 'agent/linux_bash_command_provider.dart';
import '../application/draft_agent_service.dart';
import '../presentation/controllers/speech_service.dart';
import '../application/speech/speech_runtime.dart';
import '../core/ports/speech_provider.dart';
import '../core/ports/remote_speech_provider.dart';
import '../core/ports/speech_settings_repository.dart';
import 'speech/http_remote_speech_provider.dart';
import 'speech/remote_speech_settings_store.dart';
import 'speech/local_sense_voice_provider.dart';
import 'backup/life_vault_archive.dart';
import 'backup/vault_restore_transaction.dart';
import 'blob/encrypted_blob_store.dart';
import 'ocr/google_mlkit_ocr_provider.dart';
import 'persistence/app_database.dart';
import 'persistence/sqlite_vault_repository.dart';
import 'security/android_biometric_key_store.dart';
import 'security/android_device_factor_protection.dart';

/// Single composition entry for the app and isolated native verification.
/// Defaults belong here; the controller never constructs platform services.
AppPreferences createAppPreferences([File? file]) => AppPreferences(
  DevicePreferencesRuntime(FileDevicePreferencesRepository(file)),
);

RecipientService createRecipientService(
  Future<Directory> Function() resolveDirectory,
) => RecipientService(RecipientRuntime(FileRecipientStore(resolveDirectory)));

DeviceCapabilities currentDeviceCapabilities() => DeviceCapabilities(
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

AppController createAppController([
  Directory? applicationDirectory,
  BiometricKeyStore? biometricKeyStore,
  OcrProvider? ocrProvider,
  AiProvider? aiProvider,
  AiSettingsRepository? aiSettingsStore,
  Future<void> Function(String stage)? restoreCheckpoint,
  DeviceFactorProtection? deviceFactorProtection,
  DateTime Function()? clock,
  SpeechService? speechService,
  OutboundConsentRepository? outboundConsentStore,
]) {
  final session = VaultSession(
    installationFactory: (directory) => VaultRestoreTransaction(directory),
    resolveDirectory: () async {
      final support =
          applicationDirectory ?? await getApplicationSupportDirectory();
      return Directory('${support.path}/live_relay/vault');
    },
    loadPassphraseCodec: () async => ChinesePassphraseCodec.parse(
      await rootBundle.loadString(
        'assets/wordlists/new-default-pinyin.wordlist',
      ),
    ),
    openRepository: (directory, key) async => SqliteVaultRepository(
      await AppDatabase.openEncrypted(
        vaultDirectory: directory,
        masterKey: key,
      ),
      clock: clock,
    ),
    biometricKeyStore: biometricKeyStore ?? AndroidBiometricKeyStore(),
    blobStore: EncryptedBlobStore(),
    deviceFactorProtection:
        deviceFactorProtection ?? AndroidDeviceFactorProtection(),
  );
  final archive = LifeVaultArchiveService();
  final backup = VaultBackupService(
    session: session,
    archive: archive,
    restoreTransaction: () => VaultRestoreTransaction(
      session.directory,
      checkpoint: restoreCheckpoint,
    ),
  );
  final transfer = DeviceTransferService(backup: backup, archive: archive);
  final selectedAi = aiProvider ?? ConfiguredAiProvider();
  final speech =
      speechService ??
      createSpeechService(
        LocalSenseVoiceProvider(() async {
          final support =
              applicationDirectory ?? await getApplicationSupportDirectory();
          return Directory('${support.path}/live_relay/speech');
        }),
      );
  final commands = LinuxBashCommandProvider(
    resolveDirectory: () async {
      final support =
          applicationDirectory ?? await getApplicationSupportDirectory();
      return Directory('${support.path}/live_relay/agent_runtime');
    },
  );
  final agentSettings = AgentSettingsService(
    aiSettingsStore ?? AiProviderSettingsStore(),
  );
  final outboundConsent = OutboundConsentService(
    outboundConsentStore ?? OutboundConsentStore(),
  );
  final agent = AgentService(
    vault: session,
    configuration: agentSettings,
    provider: selectedAi,
    drafts: DraftAgentService(selectedAi, commands: commands),
  );
  final review = AgentReviewService(session);
  final snapshots = VaultSnapshotQuery(session);
  final content = VaultContentService(
    vault: session,
    ocr: ocrProvider ?? GoogleMlKitOcrProvider(),
  );
  return AppController(
    capabilities: currentDeviceCapabilities(),
    records: VaultRecordsApplication(
      vault: session,
      content: content,
      snapshots: snapshots,
      clock: clock ?? DateTime.now,
    ),
    conversationApplication: ConversationApplication(
      vault: session,
      settings: agentSettings,
      agent: agent,
      review: review,
      content: content,
      snapshots: snapshots,
    ),
    session: session,
    handoff: LocalHandoffService(session, originals: session),
    recipient: createRecipientService(() async {
      final support =
          applicationDirectory ?? await getApplicationSupportDirectory();
      return Directory('${support.path}/live_relay/recipient');
    }),
    securityService: VaultSecurityService(
      session,
      () => VaultRestoreTransaction(session.directory),
    ),
    backup: backup,
    transfer: transfer,
    content: content,
    agentSettings: agentSettings,
    outboundConsent: outboundConsent,
    agent: agent,
    agentReview: review,
    snapshotQuery: snapshots,
    speechService: speech,
    prepareEnvironment: () async {
      await _prepareEnvironment();
      try {
        await commands.cleanStaleInputs();
      } on FileSystemException {
        /* Retry on next start. */
      }
    },
  );
}

Future<void> _prepareEnvironment() async {
  try {
    await FilePicker.clearTemporaryFiles();
  } on Object {
    // Not all desktop pickers expose cache cleanup.
  }
  await _clearKnownPlaintextCache();
}

Future<void> _clearKnownPlaintextCache() async {
  try {
    final cache = await getTemporaryDirectory();
    if (!await cache.exists()) return;
    await clearPrivateCache(cache);
  } on Object {
    // Cache is outside the authenticated Vault. Cleanup is retried on every
    // start and failure must not turn into data loss or an unlock failure.
  }
}

/// Platform defaults and ownership belong to composition, not the use case.
SpeechService createSpeechService(
  SpeechProvider provider, {
  bool? supported,
  RemoteSpeechProvider? remoteProvider,
  SpeechSettingsRepository? settingsStore,
}) {
  final remote = remoteProvider ?? HttpRemoteSpeechProvider();
  return SpeechService(
    SpeechRuntime(
      provider: provider,
      supported:
          supported ??
          (Platform.isAndroid || Platform.isLinux || Platform.isWindows),
      remoteProvider: remote,
      settingsRepository: settingsStore ?? RemoteSpeechSettingsStore(),
      disposeRemote: remoteProvider == null
          ? (remote as HttpRemoteSpeechProvider).close
          : null,
    ),
  );
}
