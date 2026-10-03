import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../core/domain/entities.dart';
import '../core/ports/biometric_key_store.dart';
import '../core/ports/vault_blob_store.dart';
import '../core/ports/vault_repository.dart';
import '../core/security/chinese_passphrase.dart';
import '../core/security/vault_key_manager.dart';
import '../infrastructure/backup/vault_restore_transaction.dart'
    show VaultRecoveryException;

enum VaultSessionState { loading, needsSetup, locked, unlocked, failure }

typedef OpenVaultRepository = Future<VaultRepository> Function(
  Directory directory,
  Uint8List key,
);

/// Owns the unlocked key and database. Presentation and AI never receive keys.
class VaultSession {
  VaultSession({
    required this._resolveDirectory,
    required this._loadPassphraseCodec,
    required this._openRepository,
    required this._biometricKeyStore,
    required this._blobStore,
  });

  final Future<Directory> Function() _resolveDirectory;
  final Future<ChinesePassphraseCodec> Function() _loadPassphraseCodec;
  final OpenVaultRepository _openRepository;
  final BiometricKeyStore _biometricKeyStore;
  final VaultBlobStore _blobStore;
  late Directory _directory;
  late VaultKeyManager _keyManager;
  late ChinesePassphraseCodec _passphraseCodec;
  VaultRepository? _repository;
  Uint8List? _sessionKey;

  VaultSessionState _state = VaultSessionState.loading;
  VaultHeaderMetadata? _header;
  bool _biometricAvailable = false;
  VaultSessionState get state => _state;
  VaultHeaderMetadata? get header => _header;
  bool get biometricAvailable => _biometricAvailable;
  bool get isUnlocked => _state == VaultSessionState.unlocked;
  Directory get directory => _directory;

  Future<void> prepare() async {
    _directory = await _resolveDirectory();
    _keyManager = VaultKeyManager(_directory);
  }

  /// Called after transaction recovery, before choosing creation or unlock.
  Future<void> inspect() async {
    await loadPassphraseCodec();
    await reloadHeader();
    if (await _directory.exists()) {
      final hasFiles = !await _directory.list().isEmpty;
      if ((_header == null && hasFiles) ||
          (header != null &&
              !await File('${_directory.path}/vault.sqlite').exists())) {
        throw const VaultRecoveryException();
      }
    }
    try {
      _biometricAvailable = await _biometricKeyStore.isAvailable();
    } on Object {
      _biometricAvailable = false;
    }
    _state = _header == null
        ? VaultSessionState.needsSetup
        : VaultSessionState.locked;
  }

  void fail() => _state = VaultSessionState.failure;
  void markUnlocked() => _state = VaultSessionState.unlocked;
  Future<void> reloadHeader() async =>
      _header = await _keyManager.readMetadata();
  Future<void> inspectRecoveredHeader() async {
    await reloadHeader();
    _state = _header == null
        ? VaultSessionState.needsSetup
        : VaultSessionState.locked;
  }

  Future<void> loadPassphraseCodec() async {
    _passphraseCodec = await _loadPassphraseCodec();
  }

  ChinesePassphrase generatePassphrase({int count = 6}) =>
      _passphraseCodec.generate(count: count);

  Future<void> setupVault({
    required String password,
    required bool usesChinesePassphrase,
    int? wordCount,
    bool enableBiometric = false,
  }) async {
    if (state != VaultSessionState.needsSetup) {
      throw StateError('当前资料库状态不允许创建，请先处理恢复状态');
    }
    final canonical = usesChinesePassphrase
        ? _passphraseCodec.canonicalize(password, wordCount: wordCount ?? 6)
        : password;
    final key = await _keyManager.create(
      canonicalPassword: canonical,
      passwordKind: usesChinesePassphrase ? 'diceware-cn-v1' : 'custom',
      wordCount: usesChinesePassphrase ? wordCount : null,
    );
    try {
      await openWithKey(key);
      if (enableBiometric && biometricAvailable) {
        await _biometricKeyStore.saveMasterKey(key);
        await _keyManager.setBiometricEnabled(true);
      }
    } finally {
      _wipe(key);
    }
    await reloadHeader();
    _state = VaultSessionState.unlocked;
  }

  Future<void> unlockWithPassword(String password) async {
    if (_state == VaultSessionState.failure) {
      throw const VaultRecoveryException();
    }
    final metadata = header ?? await _keyManager.readMetadata();
    if (metadata == null) throw StateError('加密资料库尚未创建');
    final canonical = metadata.usesChinesePassphrase
        ? _passphraseCodec.canonicalize(
            password,
            wordCount: metadata.wordCount ?? 6,
          )
        : password;
    final key = await _keyManager.unlock(canonical);
    try {
      await openWithKey(key);
    } finally {
      _wipe(key);
    }
    _state = VaultSessionState.unlocked;
  }

  Future<void> unlockWithBiometric() async {
    if (_state == VaultSessionState.failure) {
      throw const VaultRecoveryException();
    }
    final metadata = await _keyManager.readMetadata();
    if (metadata == null || !metadata.biometricEnabled || !biometricAvailable) {
      throw StateError('当前资料库未启用可用的指纹解锁，请使用密码');
    }
    final key = await _biometricKeyStore.readMasterKey();
    if (key == null) throw StateError('设备中没有可用的指纹密钥槽');
    try {
      await openWithKey(key);
    } finally {
      _wipe(key);
    }
    _state = VaultSessionState.unlocked;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (!isUnlocked) throw StateError('请先解锁加密资料库');
    if (enabled) {
      throw UnsupportedError('启用指纹需要重新输入主密码');
    }
    await _biometricKeyStore.clear();
    await _keyManager.setBiometricEnabled(false);
    await reloadHeader();
  }

  Future<void> enableBiometricWithPassword(String password) async {
    if (!biometricAvailable) throw StateError('当前设备没有可用的强生物识别');
    final metadata = header!;
    final canonical = metadata.usesChinesePassphrase
        ? _passphraseCodec.canonicalize(
            password,
            wordCount: metadata.wordCount ?? 6,
          )
        : password;
    final key = await _keyManager.unlock(canonical);
    try {
      await _biometricKeyStore.saveMasterKey(key);
      await _keyManager.setBiometricEnabled(true);
    } finally {
      _wipe(key);
    }
    await reloadHeader();
  }

  /// Internal service use: authenticate an export password independently.
  Future<Uint8List> authenticatePassword(String password) async {
    final metadata = header ?? await _keyManager.readMetadata();
    if (metadata == null) throw StateError('加密资料库尚未创建');
    return _keyManager.unlock(canonicalizePassword(password, metadata));
  }

  String canonicalizePassword(String password, VaultHeaderMetadata metadata) =>
      metadata.usesChinesePassphrase
      ? _passphraseCodec.canonicalize(
          password,
          wordCount: metadata.wordCount ?? 6,
        )
      : password;

  /// Opens a temporary verified backup without changing the active session.
  Future<VaultRepository> openTemporary(Directory directory, Uint8List key) =>
      _openRepository(directory, key);

  Future<void> openWithKey(Uint8List key) async {
    await suspendDatabase();
    final repository = await _openRepository(_directory, key);
    _repository = repository;
    _clearSessionKey();
    _sessionKey = Uint8List.fromList(key);
  }

  /// Export needs closed SQLite files while retaining its current UI state.
  Future<void> suspendDatabase() async {
    final repository = _repository;
    _repository = null;
    if (repository != null) await repository.close();
  }

  Future<void> close() async {
    try {
      await suspendDatabase();
    } finally {
      _clearSessionKey();
      if (state != VaultSessionState.failure) _state = VaultSessionState.locked;
    }
  }

  Future<void> clearDeviceKeyAfterRestore() async {
    try {
      await _biometricKeyStore.clear();
    } on Object {
      // Restored headers disable biometrics before installation. Stale slots
      // cannot be read even when the platform refuses cleanup.
    }
  }

  VaultRepository get repository {
    final repository = _repository;
    if (repository == null) throw StateError('加密资料库尚未解锁');
    return repository;
  }

  Uint8List get _key {
    final key = _sessionKey;
    if (key == null) throw StateError('加密资料库尚未解锁');
    return key;
  }

  Future<VaultBlob> writeOriginal({
    required Uint8List bytes,
    required String originalName,
    required String mimeType,
    required BlobMediaKind mediaKind,
  }) => _blobStore.write(
    vaultDirectory: _directory,
    masterKey: _key,
    clearBytes: bytes,
    originalName: originalName,
    mimeType: mimeType,
    mediaKind: mediaKind,
  );

  Future<Uint8List> readOriginal(VaultBlob blob) =>
      _blobStore.read(vaultDirectory: _directory, masterKey: _key, blob: blob);

  Future<void> deleteOriginal(VaultBlob blob) =>
      _blobStore.delete(vaultDirectory: _directory, blob: blob);

  void _clearSessionKey() {
    final key = _sessionKey;
    _sessionKey = null;
    if (key != null) _wipe(key);
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  void dispose() {
    final repository = _repository;
    _repository = null;
    _clearSessionKey();
    if (repository != null) unawaited(repository.close());
  }
}
