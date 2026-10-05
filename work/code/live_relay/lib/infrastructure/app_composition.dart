import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../application/app_controller.dart';
import '../application/vault_backup_service.dart';
import '../application/vault_session.dart';
import '../application/vault_security_service.dart';
import '../application/local_handoff_service.dart';
import '../application/recipient_service.dart';
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
import '../application/speech_service.dart';
import 'speech/local_sense_voice_provider.dart';
import 'backup/life_vault_archive.dart';
import 'backup/vault_restore_transaction.dart';
import 'blob/encrypted_blob_store.dart';
import 'import/edge_password_csv_importer.dart';
import 'ocr/google_mlkit_ocr_provider.dart';
import 'persistence/app_database.dart';
import 'persistence/sqlite_vault_repository.dart';
import 'security/android_biometric_key_store.dart';
import 'security/android_device_factor_protection.dart';

/// Single composition entry for the app and isolated native verification.
/// Defaults belong here; the controller never constructs platform services.
AppController createAppController([
  Directory? applicationDirectory,
  BiometricKeyStore? biometricKeyStore,
  OcrProvider? ocrProvider,
  AiProvider? aiProvider,
  AiProviderSettingsStore? aiSettingsStore,
  Future<void> Function(String stage)? restoreCheckpoint,
  DeviceFactorProtection? deviceFactorProtection,
  DateTime Function()? clock,
  SpeechService? speechService,
]) {
  final session = VaultSession(
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
  final backup = VaultBackupService(
    session: session,
    archive: LifeVaultArchiveService(),
    restoreTransaction: () => VaultRestoreTransaction(
      session.directory,
      checkpoint: restoreCheckpoint,
    ),
  );
  final selectedAi = aiProvider ?? ConfiguredAiProvider();
  final speech =
      speechService ??
      SpeechService(
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
  return AppController(
    session: session,
    handoff: LocalHandoffService(session),
    recipient: RecipientService(() async {
      final support =
          applicationDirectory ?? await getApplicationSupportDirectory();
      return Directory('${support.path}/live_relay/recipient');
    }),
    securityService: VaultSecurityService(
      session,
      () => VaultRestoreTransaction(session.directory),
    ),
    backup: backup,
    ocrProvider: ocrProvider ?? GoogleMlKitOcrProvider(),
    aiProvider: selectedAi,
    draftAgentService: DraftAgentService(selectedAi, commands: commands),
    speechService: speech,
    aiSettingsStore: aiSettingsStore ?? AiProviderSettingsStore(),
    edgeImporter: const EdgePasswordCsvImporter(),
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
