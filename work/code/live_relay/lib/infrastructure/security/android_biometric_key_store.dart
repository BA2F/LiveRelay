import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../../core/ports/biometric_key_store.dart';

class AndroidBiometricKeyStore implements BiometricKeyStore {
  AndroidBiometricKeyStore({
    FlutterSecureStorage? storage,
    LocalAuthentication? authentication,
  }) : _storage =
           storage ??
           const FlutterSecureStorage(
             aOptions: AndroidOptions.biometric(
               resetOnError: false,
               enforceBiometrics: true,
               requireBiometricsPerOperation: true,
               biometricType: AndroidBiometricType.strongBiometricOnly,
               biometricPromptTitle: '用指纹解锁留灯',
               biometricPromptSubtitle: '授权设备密钥读取 Vault 主密钥',
               storageNamespace: 'liverelay_vault_biometric_v1',
             ),
           ),
       _authentication = authentication ?? LocalAuthentication();

  static const _key = 'vault-master-key-v1';

  final FlutterSecureStorage _storage;
  final LocalAuthentication _authentication;

  @override
  Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    if (!await _authentication.canCheckBiometrics) return false;
    final enrolled = await _authentication.getAvailableBiometrics();
    return enrolled.contains(BiometricType.fingerprint) ||
        enrolled.contains(BiometricType.strong);
  }

  @override
  Future<void> saveMasterKey(Uint8List masterKey) {
    return _storage.write(key: _key, value: base64UrlEncode(masterKey));
  }

  @override
  Future<Uint8List?> readMasterKey() async {
    if (!Platform.isAndroid) return null;
    final encoded = await _storage.read(key: _key);
    return encoded == null ? null : base64Url.decode(encoded);
  }

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
