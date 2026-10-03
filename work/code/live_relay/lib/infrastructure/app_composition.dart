import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../application/app_controller.dart';
import '../application/vault_backup_service.dart';
import '../application/vault_session.dart';
import '../core/ports/ai_provider.dart';
import '../core/ports/biometric_key_store.dart';
import '../core/ports/ocr_provider.dart';
import '../core/security/chinese_passphrase.dart';
import 'ai/ai_provider_settings_store.dart';
import 'ai/openai_compatible_provider.dart';
import 'backup/life_vault_archive.dart';
import 'backup/vault_restore_transaction.dart';
import 'blob/encrypted_blob_store.dart';
import 'import/edge_password_csv_importer.dart';
import 'ocr/google_mlkit_ocr_provider.dart';
import 'persistence/app_database.dart';
import 'persistence/sqlite_vault_repository.dart';
import 'security/android_biometric_key_store.dart';

/// Single composition entry for the app and isolated native verification.
/// Defaults belong here; the controller never constructs platform services.
AppController createAppController([
  Directory? applicationDirectory,
  BiometricKeyStore? biometricKeyStore,
  OcrProvider? ocrProvider,
  AiProvider? aiProvider,
  AiProviderSettingsStore? aiSettingsStore,
  Future<void> Function(String stage)? restoreCheckpoint,
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
    ),
    biometricKeyStore: biometricKeyStore ?? AndroidBiometricKeyStore(),
    blobStore: EncryptedBlobStore(),
  );
  final backup = VaultBackupService(
    session: session,
    archive: LifeVaultArchiveService(),
    restoreTransaction: () => VaultRestoreTransaction(
      session.directory,
      checkpoint: restoreCheckpoint,
    ),
  );
  return AppController(
    session: session,
    backup: backup,
    ocrProvider: ocrProvider ?? GoogleMlKitOcrProvider(),
    aiProvider: aiProvider ?? OpenAiCompatibleProvider(),
    aiSettingsStore: aiSettingsStore ?? AiProviderSettingsStore(),
    edgeImporter: const EdgePasswordCsvImporter(),
    prepareEnvironment: _prepareEnvironment,
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
    const mediaExtensions = <String>{
      '.jpg',
      '.jpeg',
      '.png',
      '.webp',
      '.heic',
      '.mp3',
      '.m4a',
      '.wav',
      '.aac',
      '.mp4',
      '.mov',
      '.webm',
    };
    await for (final entity in cache.list(recursive: true)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path).toLowerCase();
      final isKnownTemporary =
          name.startsWith('ocr-') ||
          name.startsWith('recording-') ||
          name.startsWith('view-') ||
          mediaExtensions.contains(path.extension(name));
      if (isKnownTemporary) await entity.delete();
    }
  } on Object {
    // Cache is outside the authenticated Vault. Cleanup is retried on every
    // start and failure must not turn into data loss or an unlock failure.
  }
}
