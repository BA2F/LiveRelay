import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:live_relay/core/ports/device_factor_protection.dart';

/// Software fixture only. Never a production substitute for Keystore.
class FictionalDeviceProtection implements DeviceFactorProtection {
  final _keys = <String, SecretKey>{};
  int reads = 0;
  int deletes = 0;
  bool available = true;
  DeviceFactorFailure? failure;
  Uint8List? borrowedShare;
  Future<void>? holdRead;
  final _cipher = AesGcm.with256bits();

  @override
  Future<DeviceFactorCapability> capability() async => DeviceFactorCapability(
    available: available,
    reason: 'software fixture',
    strongBiometricOnly: true,
    perOperationAuthorization: true,
    invalidatedByEnrollment: true,
  );

  @override
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  ) async {
    borrowedShare = share;
    if (failure != null) throw DeviceFactorException(failure!);
    final key = await _cipher.newSecretKey();
    _keys[context.reference] = key;
    final box = await _cipher.encrypt(share, secretKey: key, aad: context.aad);
    return WrappedDeviceFactor(
      nonce: Uint8List.fromList(box.nonce),
      cipherText: Uint8List.fromList(box.cipherText),
      mac: Uint8List.fromList(box.mac.bytes),
    );
  }

  @override
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor wrapped,
  ) async {
    reads++;
    await holdRead;
    if (failure != null) throw DeviceFactorException(failure!);
    final key = _keys[context.reference];
    if (key == null) {
      throw const DeviceFactorException(DeviceFactorFailure.missing);
    }
    return Uint8List.fromList(
      await _cipher.decrypt(
        SecretBox(
          wrapped.cipherText,
          nonce: wrapped.nonce,
          mac: Mac(wrapped.mac),
        ),
        secretKey: key,
        aad: context.aad,
      ),
    );
  }

  @override
  Future<void> deleteFactor(String reference) async {
    deletes++;
    _keys.remove(reference)?.destroy();
  }

  @override
  Future<void> cancel() async {}
}
