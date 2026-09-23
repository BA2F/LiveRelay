import 'dart:typed_data';

abstract interface class BiometricKeyStore {
  Future<bool> isAvailable();

  Future<void> saveMasterKey(Uint8List masterKey);

  Future<Uint8List?> readMasterKey();

  Future<void> clear();
}
