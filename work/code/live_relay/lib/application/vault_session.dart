import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../core/domain/entities.dart';
import '../core/ports/biometric_key_store.dart';
import '../core/ports/device_factor_protection.dart';
import '../core/ports/vault_blob_store.dart';
import '../core/ports/vault_repository.dart';
import '../core/ports/vault_originals.dart';
import '../core/security/chinese_passphrase.dart';
import '../core/security/vault_key_manager.dart';
import '../core/security/vault_header_v3.dart';
import '../core/security/recovery_credential.dart';
import '../infrastructure/backup/vault_restore_transaction.dart'
    show VaultRecoveryException, VaultRestoreTransaction;

enum VaultSessionState {
  loading,
  needsSetup,
  locked,
  unlocked,
  recovering,
  failure,
}

typedef OpenVaultRepository = Future<VaultRepository> Function(
  Directory directory,
  Uint8List key,
);

/// Owns the unlocked key and database. Presentation and AI never receive keys.
class VaultSession implements VaultOriginals {
  VaultSession({
    required this._resolveDirectory,
    required this._loadPassphraseCodec,
    required this._openRepository,
    required this._biometricKeyStore,
    required this._blobStore,
    this._deviceFactorProtection,
  });

  final Future<Directory> Function() _resolveDirectory;
  final Future<ChinesePassphraseCodec> Function() _loadPassphraseCodec;
  final OpenVaultRepository _openRepository;
  final BiometricKeyStore _biometricKeyStore;
  final VaultBlobStore _blobStore;
  final DeviceFactorProtection? _deviceFactorProtection;
  int _deviceOperationEpoch = 0;
  int _sessionGeneration = 0;
  @override
  int get sessionGeneration => _sessionGeneration;
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
  @override
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
      _biometricAvailable = (_header?.formatVersion ?? 3) >= 2
          ? (await _deviceFactorProtection?.capability())
                    ?.supportsRequiredProtection ??
                false
          : await _biometricKeyStore.isAvailable();
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
      _biometricAvailable = await _biometricKeyStore.isAvailable();
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
    if (metadata.formatVersion == 3) {
      await unlockDaily(password: password);
      return;
    }
    final key = await _keyManager.unlock(canonical);
    try {
      await openWithKey(key);
    } finally {
      _wipe(key);
    }
    _state = VaultSessionState.unlocked;
  }

  int get operationEpoch => _deviceOperationEpoch;
  Future<T> withMasterKey<T>(
    Future<T> Function(Uint8List key) operation,
  ) async {
    if (!isUnlocked && state != VaultSessionState.recovering) {
      throw StateError('请先认证');
    }
    final copy = Uint8List.fromList(_key);
    try {
      return await operation(copy);
    } finally {
      _wipe(copy);
    }
  }

  Future<Uint8List> authenticateDaily(
    String password, {
    Uint8List? keyFile,
  }) async {
    if (header?.formatVersion != 3) return authenticatePassword(password);
    return _keyManager.unlockDaily(
      password: canonicalizePassword(password, header!),
      keyFile: keyFile,
      device: _deviceFactorProtection,
    );
  }

  Future<void> unlockDaily({
    String? password,
    Uint8List? keyFile,
    String preferred = 'password',
  }) async {
    final epoch = operationEpoch;
    final key = await _keyManager.unlockDaily(
      password: password == null
          ? null
          : canonicalizePassword(password, header!),
      keyFile: keyFile,
      device: _deviceFactorProtection,
      preferred: preferred,
    );
    try {
      if (epoch != operationEpoch) throw StateError('解锁已取消');
      await openWithKey(key);
      if (epoch != operationEpoch) {
        await close();
        throw StateError('解锁已取消');
      }
      _state = VaultSessionState.unlocked;
    } finally {
      _wipe(key);
    }
  }

  Future<void> createModern({
    required String password,
    required RecoveryCredential recovery,
    bool usesChinesePassphrase = false,
    int? wordCount,
    bool enableBiometric = false,
  }) async {
    if (state != VaultSessionState.needsSetup) throw StateError('当前不能创建');
    final canonical = usesChinesePassphrase
        ? _passphraseCodec.canonicalize(password, wordCount: wordCount ?? 6)
        : password;
    final key = Uint8List.fromList(
      List.generate(32, (_) => Random.secure().nextInt(256)),
    );
    VaultHeaderV3? candidate;
    Directory? staging;
    final epoch = operationEpoch;
    final transaction = VaultRestoreTransaction(directory);
    var installationStarted = false;
    try {
      candidate = await VaultHeaderV3.create(
        password: canonical,
        masterKey: key,
        recovery: recovery,
        passwordKind: usesChinesePassphrase ? 'diceware-cn-v1' : 'custom',
        wordCount: usesChinesePassphrase ? wordCount : null,
        device: enableBiometric ? _deviceFactorProtection : null,
      );
      await directory.parent.create(recursive: true);
      staging = await directory.parent.createTemp('liverelay-restore-');
      await VaultKeyManager(staging).writeV3(candidate);
      final test = await openTemporary(staging, key);
      await test.close();
      if (epoch != operationEpoch) throw StateError('创建已取消');
      if (await directory.exists()) {
        if (!await directory.list().isEmpty) throw StateError('目标目录已有资料，已保留');
        await directory.delete();
      }
      installationStarted = true;
      await transaction.install(
        staging,
        verifyInstalled: () async {
          if (epoch != operationEpoch) throw StateError('创建已取消');
          await openWithKey(key);
          await reloadHeader();
          if (epoch != operationEpoch) throw StateError('创建已取消');
        },
        closeInstalled: close,
      );
      _state = VaultSessionState.unlocked;
    } on Object {
      await close();
      if (installationStarted) {
        try {
          await transaction.recover();
          await inspectRecoveredHeader();
        } catch (_) {
          fail();
        }
      }
      // First installation may deliberately retain the complete new vault.
      for (final ref
          in !installationStarted
              ? candidate?.deviceReferences ?? <String>[]
              : <String>[]) {
        try {
          await _deviceFactorProtection?.deleteFactor(ref);
        } on Object {
          /* detached reference */
        }
      }
      rethrow;
    } finally {
      if (staging != null && await staging.exists()) {
        await staging.delete(recursive: true);
      }
      _wipe(key);
    }
  }

  Future<VaultHeaderV3?> modernHeader() => _keyManager.readV3();
  VaultBlobStore get blobStore => _blobStore;
  DeviceFactorProtection? get deviceProtection => _deviceFactorProtection;
  Future<void> copyBlobUnderKey({
    required Directory target,
    required Uint8List oldKey,
    required Uint8List newKey,
    required VaultBlob blob,
  }) => _blobStore.copyUnderKey(
    source: directory,
    target: target,
    oldKey: oldKey,
    newKey: newKey,
    blob: blob,
  );

  /// Recovery opens only the reset workflow, without normal page projections.
  Future<Uint8List> authenticateRecovery(String text) =>
      _keyManager.unlockWithRecovery(text);
  void markRecovering() {
    _state = VaultSessionState.recovering;
  }

  Future<void> unlockWithRecovery(String encodedRecovery) async {
    final epoch = operationEpoch;
    if (_state == VaultSessionState.failure) {
      throw const VaultRecoveryException();
    }
    final key = await _keyManager.unlockWithRecovery(encodedRecovery);
    try {
      if (epoch != operationEpoch) throw StateError('恢复已取消');
      await openWithKey(key);
      if (epoch != operationEpoch) {
        await close();
        throw StateError('恢复已取消');
      }
    } finally {
      _wipe(key);
    }
    _state = VaultSessionState.recovering;
  }

  Future<void> unlockWithBiometric() async {
    if (_state == VaultSessionState.failure) {
      throw const VaultRecoveryException();
    }
    final epoch = _deviceOperationEpoch;
    final metadata = await _keyManager.readMetadata();
    if (metadata == null || !metadata.biometricEnabled || !biometricAvailable) {
      throw StateError('当前资料库未启用可用的指纹解锁，请使用密码');
    }
    if (metadata.formatVersion == 3) {
      await unlockDaily(preferred: 'device');
      return;
    }
    final key = metadata.formatVersion == 2
        ? await _keyManager.unlockWithDevice(
            _deviceFactorProtection ??
                (throw const DeviceFactorException(
                  DeviceFactorFailure.unavailable,
                )),
          )
        : await _biometricKeyStore.readMasterKey();
    if (key == null) throw StateError('设备中没有可用的指纹密钥槽');
    try {
      if (metadata.formatVersion == 2 && epoch != _deviceOperationEpoch) {
        throw const DeviceFactorException(DeviceFactorFailure.cancelled);
      }
      await openWithKey(key);
      if (metadata.formatVersion == 2 && epoch != _deviceOperationEpoch) {
        await close();
        throw const DeviceFactorException(DeviceFactorFailure.cancelled);
      }
    } finally {
      _wipe(key);
    }
    _state = VaultSessionState.unlocked;
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    if (!isUnlocked) throw StateError('请先解锁加密资料库');
    if (header?.formatVersion != 1) {
      throw UnsupportedError('此资料库暂不支持修改指纹设置');
    }
    if (enabled) {
      throw UnsupportedError('启用指纹需要重新输入主密码');
    }
    await _biometricKeyStore.clear();
    await _keyManager.setBiometricEnabled(false);
    await reloadHeader();
  }

  Future<void> enableBiometricWithPassword(String password) async {
    final metadata = header!;
    if (metadata.formatVersion != 1) {
      throw UnsupportedError('此资料库暂不支持修改指纹设置');
    }
    if (!biometricAvailable) throw StateError('当前设备没有可用的强生物识别');
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
    _sessionGeneration++;
    final repository = _repository;
    _repository = null;
    if (repository != null) await repository.close();
  }

  Future<void> close() async {
    _sessionGeneration++;
    _deviceOperationEpoch++;
    try {
      await _deviceFactorProtection?.cancel();
    } on Object {
      // Locking still closes the database if the platform channel is gone.
    }
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

  @override
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

  @override
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

  @override
  Future<Uint8List> readOriginal(VaultBlob blob) {
    final r = repository;
    final key = _key;
    return _readOriginal(r, key, blob);
  }

  Future<Uint8List> _readOriginal(
    VaultRepository r,
    Uint8List key,
    VaultBlob blob,
  ) async {
    if (header?.formatVersion == 3) {
      final missing = await r.readLocalValue('backup.missing');
      if (missing != null &&
          (jsonDecode(missing) as Map).containsKey(blob.relativePath)) {
        throw StateError('此原件尚未恢复，请导入与数据库包配对的原件补充包');
      }
    }
    return _blobStore.read(
      vaultDirectory: _directory,
      masterKey: key,
      blob: blob,
    );
  }

  @override
  Future<void> deleteOriginal(VaultBlob blob) =>
      _blobStore.delete(vaultDirectory: _directory, blob: blob);

  void _clearSessionKey() {
    final key = _sessionKey;
    _sessionKey = null;
    if (key != null) _wipe(key);
  }

  void _wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);

  void dispose() {
    _deviceOperationEpoch++;
    unawaited(_deviceFactorProtection?.cancel().catchError((Object _) {}));
    final repository = _repository;
    _repository = null;
    _clearSessionKey();
    if (repository != null) unawaited(repository.close());
  }
}
