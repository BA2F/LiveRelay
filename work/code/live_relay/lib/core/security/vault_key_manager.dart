import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'vault_password_policy.dart';
import 'vault_header_v2.dart';
import 'vault_header_v3.dart';
import 'recovery_credential.dart';
import 'header_encoding.dart';
import '../storage/recoverable_file.dart';
import '../ports/device_factor_protection.dart';

class VaultUnlockException implements Exception {
  const VaultUnlockException([this.message = '主密码不正确或 Vault 已损坏']);

  final String message;

  @override
  String toString() => message;
}

class VaultHeaderMetadata {
  const VaultHeaderMetadata({
    required this.passwordKind,
    required this.wordCount,
    required this.biometricEnabled,
    required this.createdAt,
    this.formatVersion = 1,
    this.recoveryEnabled = false,
    this.dailyPolicy = 'any',
    this.keyFileEnabled = false,
  });

  final int formatVersion;
  final bool recoveryEnabled;
  final String dailyPolicy;
  final bool keyFileEnabled;
  final String passwordKind;
  final int? wordCount;
  final bool biometricEnabled;
  final DateTime createdAt;

  bool get usesChinesePassphrase => passwordKind == 'diceware-cn-v1';
}

/// Owns the small, non-sensitive vault header and the password key slot.
/// Structured data is encrypted separately with the returned random master key.
class VaultKeyManager {
  VaultKeyManager(this.rootDirectory, {this.writeCheckpoint});

  final Future<void> Function(String stage)? writeCheckpoint;

  static const _aad = 'LiveRelay/VaultMasterKey/v1';
  static const _headerName = 'vault-header.json';
  static const _argonMemoryKiB = 19 * 1024;
  static const _argonIterations = 2;
  static const _argonParallelism = 1;

  final Directory rootDirectory;

  File get headerFile => File('${rootDirectory.path}/$_headerName');

  Future<bool> exists() async {
    await _recoverHeader();
    return headerFile.exists();
  }

  Future<void> _recoverHeader() => RecoverableFile(headerFile).recover((bytes) {
    try {
      final header = jsonDecode(utf8.decode(bytes));
      if (header is Map && header['formatVersion'] == 3) {
        VaultHeaderV3.decode(bytes);
        return true;
      }
      if (header is Map && header['formatVersion'] == 2) {
        VaultHeaderV2.decode(bytes);
        return true;
      }
      return header is Map &&
          header['formatVersion'] == 1 &&
          header['passwordSlot'] is Map &&
          header['kdf'] is Map &&
          header['passwordKind'] is String &&
          DateTime.tryParse(header['createdAt'] as String? ?? '') != null;
    } on Object {
      return false;
    }
  });

  Future<VaultHeaderMetadata?> readMetadata() async {
    if (!await exists()) return null;
    final header = await _readHeader();
    return _metadataFromHeader(header);
  }

  Future<Uint8List> create({
    required String canonicalPassword,
    required String passwordKind,
    int? wordCount,
  }) async {
    if (await exists()) throw StateError('Vault 已存在');
    final validationError = VaultPasswordPolicy.creationError(
      canonicalPassword,
    );
    if (validationError != null) throw FormatException(validationError);
    await rootDirectory.create(recursive: true);

    final masterKey = _randomBytes(32);
    final salt = _randomBytes(16);
    final wrappingKey = await _deriveKey(canonicalPassword, salt);
    final cipher = AesGcm.with256bits();
    final nonce = _randomBytes(12);
    final box = await cipher.encrypt(
      masterKey,
      secretKey: wrappingKey,
      nonce: nonce,
      aad: utf8.encode(_aad),
    );
    final now = DateTime.now().toUtc();
    final header = <String, Object?>{
      'formatVersion': 1,
      'databaseCipher': 'sqlcipher',
      'createdAt': now.toIso8601String(),
      'passwordKind': passwordKind,
      'wordCount': wordCount,
      'biometricEnabled': false,
      'kdf': <String, Object>{
        'algorithm': 'argon2id',
        'version': 19,
        'memoryKiB': _argonMemoryKiB,
        'iterations': _argonIterations,
        'parallelism': _argonParallelism,
        'hashLength': 32,
        'salt': base64UrlEncode(salt),
      },
      'passwordSlot': <String, Object>{
        'algorithm': 'aes-256-gcm',
        'nonce': base64UrlEncode(box.nonce),
        'cipherText': base64UrlEncode(box.cipherText),
        'mac': base64UrlEncode(box.mac.bytes),
      },
    };
    await _writeHeader(header);
    return masterKey;
  }

  Future<Uint8List> unlock(String canonicalPassword) async {
    try {
      final header = await _readHeader();
      if (header['formatVersion'] == 3) {
        return await VaultHeaderV3.decode(HeaderEncoding.encode(header))
            .unlock(password: canonicalPassword);
      }
      if (header['formatVersion'] == 2) {
        return await VaultHeaderV2.decode(HeaderEncoding.encode(header))
            .unlockPassword(canonicalPassword);
      }
      if (header['formatVersion'] != 1) {
        throw const VaultUnlockException('不支持此 Vault 格式版本');
      }
      final kdf = Map<String, Object?>.from(header['kdf']! as Map);
      if (kdf['algorithm'] != 'argon2id' ||
          kdf['version'] != 19 ||
          kdf['memoryKiB'] != _argonMemoryKiB ||
          kdf['iterations'] != _argonIterations ||
          kdf['parallelism'] != _argonParallelism ||
          kdf['hashLength'] != 32) {
        throw const VaultUnlockException('不支持此 Vault KDF');
      }
      final slot = Map<String, Object?>.from(header['passwordSlot']! as Map);
      if (slot['algorithm'] != 'aes-256-gcm') {
        throw const VaultUnlockException('不支持此 Vault 封装算法');
      }
      final ciphertext = base64Url.decode(slot['cipherText']! as String);
      final nonce = base64Url.decode(slot['nonce']! as String);
      final mac = base64Url.decode(slot['mac']! as String);
      if (ciphertext.length != 32 || nonce.length != 12 || mac.length != 16) {
        throw const VaultUnlockException();
      }
      final salt = base64Url.decode(kdf['salt']! as String);
      if (salt.length != 16) throw const VaultUnlockException();
      final key = await _deriveKey(
        canonicalPassword,
        salt,
        memoryKiB: kdf['memoryKiB']! as int,
        iterations: kdf['iterations']! as int,
        parallelism: kdf['parallelism']! as int,
        hashLength: kdf['hashLength']! as int,
      );
      final box = SecretBox(ciphertext, nonce: nonce, mac: Mac(mac));
      final clear = await AesGcm.with256bits().decrypt(
        box,
        secretKey: key,
        aad: utf8.encode(_aad),
      );
      if (clear.length != 32) throw const VaultUnlockException();
      return Uint8List.fromList(clear);
    } on VaultUnlockException {
      rethrow;
    } on SecretBoxAuthenticationError {
      throw const VaultUnlockException();
    } on Object {
      throw const VaultUnlockException();
    }
  }

  Future<Uint8List> unlockWithRecovery(String encodedRecovery) async {
    RecoveryCredential? recovery;
    try {
      final header = await _readHeader();
      if (![2, 3].contains(header['formatVersion'])) {
        throw const VaultUnlockException('此资料库没有独立恢复凭证');
      }
      recovery = await RecoveryCredential.parse(encodedRecovery);
      if (header['formatVersion'] == 3) {
        return await VaultHeaderV3.decode(HeaderEncoding.encode(header))
            .unlock(recovery: recovery);
      }
      return await VaultHeaderV2.decode(HeaderEncoding.encode(header))
          .unlockRecovery(recovery);
    } on VaultUnlockException {
      rethrow;
    } on Object {
      throw const VaultUnlockException('恢复凭证不正确或 Vault 已损坏');
    } finally {
      recovery?.dispose();
    }
  }

  Future<Uint8List> unlockWithDevice(DeviceFactorProtection protection) async {
    try {
      final header = await _readHeader();
      if (header['formatVersion'] != 2) {
        throw const DeviceFactorException(DeviceFactorFailure.rejected);
      }
      return await VaultHeaderV2.decode(HeaderEncoding.encode(header))
          .unlockDevice(protection);
    } on DeviceFactorException {
      rethrow;
    } on Object {
      throw const DeviceFactorException(DeviceFactorFailure.rejected);
    }
  }

  Future<void> setBiometricEnabled(bool value) async {
    final header = await _readHeader();
    if (header['formatVersion'] != 1) {
      throw const VaultUnlockException('此资料库的指纹设置需要认证重封装');
    }
    header['biometricEnabled'] = value;
    await _writeHeader(header);
  }

  Future<Map<String, Object?>> _readHeader() async {
    await _recoverHeader();
    if (await headerFile.length() > 64 * 1024) {
      throw const FormatException('Vault header 超出允许大小');
    }
    final file = await headerFile.open();
    late final List<int> bytes;
    try {
      bytes = await file.read(64 * 1024 + 1);
    } finally {
      await file.close();
    }
    if (bytes.length > 64 * 1024) {
      throw const FormatException('Vault header 超出允许大小');
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map && decoded['formatVersion'] == 3) {
      VaultHeaderV3.decode(bytes);
    }
    if (decoded is Map && decoded['formatVersion'] == 2) {
      VaultHeaderV2.decode(bytes);
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Vault header 格式错误');
    }
    return decoded;
  }

  Future<VaultHeaderV3?> readV3() async {
    final h = await _readHeader();
    return h['formatVersion'] == 3
        ? VaultHeaderV3.decode(HeaderEncoding.encode(h))
        : null;
  }

  Future<void> writeV3(VaultHeaderV3 header) async {
    await rootDirectory.create(recursive: true);
    await RecoverableFile(
      headerFile,
      checkpoint: writeCheckpoint,
    ).write(header.bytes);
  }

  Future<Uint8List> unlockDaily({
    String? password,
    Uint8List? keyFile,
    DeviceFactorProtection? device,
    String preferred = 'password',
  }) async {
    final h = await readV3();
    if (h == null) throw const VaultUnlockException('此解锁组合仅适用于新版资料库');
    try {
      return await h.unlock(
        password: password,
        keyFile: keyFile,
        device: device,
        preferred: preferred,
      );
    } on DeviceFactorException {
      rethrow;
    } on Object {
      throw const VaultUnlockException('凭证缺失、不正确或设备不可用');
    }
  }

  VaultHeaderMetadata _metadataFromHeader(Map<String, Object?> header) {
    if (header['formatVersion'] == 3) {
      final h = VaultHeaderV3.decode(HeaderEncoding.encode(header));
      return VaultHeaderMetadata(
        passwordKind: h.passwordKind,
        wordCount: h.wordCount,
        biometricEnabled: h.biometricEnabled,
        createdAt: h.createdAt,
        formatVersion: 3,
        recoveryEnabled: true,
        dailyPolicy: h.policy,
        keyFileEnabled: h.keyFileEnabled,
      );
    }
    if (header['formatVersion'] == 2) {
      final v2 = VaultHeaderV2.decode(HeaderEncoding.encode(header));
      return VaultHeaderMetadata(
        passwordKind: v2.passwordKind,
        wordCount: v2.wordCount,
        biometricEnabled: v2.biometricEnabled,
        createdAt: v2.createdAt,
        formatVersion: 2,
        recoveryEnabled: true,
      );
    }
    if (header['formatVersion'] != 1) {
      throw const VaultUnlockException('不支持此 Vault 格式版本');
    }
    return VaultHeaderMetadata(
      passwordKind: header['passwordKind']! as String,
      wordCount: header['wordCount'] as int?,
      biometricEnabled: header['biometricEnabled'] as bool? ?? false,
      createdAt: DateTime.parse(header['createdAt']! as String),
    );
  }

  Future<SecretKey> _deriveKey(
    String password,
    List<int> salt, {
    int memoryKiB = _argonMemoryKiB,
    int iterations = _argonIterations,
    int parallelism = _argonParallelism,
    int hashLength = 32,
  }) {
    return Argon2id(
      parallelism: parallelism,
      memory: memoryKiB,
      iterations: iterations,
      hashLength: hashLength,
    ).deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
  }

  Future<void> _writeHeader(Map<String, Object?> header) async {
    await RecoverableFile(
      headerFile,
      checkpoint: writeCheckpoint,
    ).write(utf8.encode(jsonEncode(header)));
  }

  Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(
      List<int>.generate(length, (_) => random.nextInt(256)),
    );
  }
}
