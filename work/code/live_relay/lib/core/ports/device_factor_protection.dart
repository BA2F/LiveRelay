import 'dart:typed_data';

/// Internal device branch contract. It never receives or stores a VMK.
class DeviceFactorCapability {
  const DeviceFactorCapability({
    required this.available,
    required this.reason,
    this.strongBiometricOnly = false,
    this.perOperationAuthorization = false,
    this.invalidatedByEnrollment = false,
  });
  final bool available;
  final String reason;
  final bool strongBiometricOnly;
  final bool perOperationAuthorization;
  final bool invalidatedByEnrollment;
  bool get supportsRequiredProtection =>
      available &&
      strongBiometricOnly &&
      perOperationAuthorization &&
      invalidatedByEnrollment;
}

enum DeviceFactorFailure {
  unavailable,
  cancelled,
  invalidated,
  missing,
  busy,
  rejected,
  failed,
}

class DeviceFactorException implements Exception {
  const DeviceFactorException(this.failure);
  final DeviceFactorFailure failure;
  @override
  String toString() => switch (failure) {
    DeviceFactorFailure.unavailable => '当前设备不支持此指纹保护，请使用密码',
    DeviceFactorFailure.cancelled => '指纹授权已取消，可重新尝试或使用密码',
    DeviceFactorFailure.invalidated => '设备密钥已失效，请使用密码',
    DeviceFactorFailure.missing => '本机没有此设备密钥，请使用密码',
    DeviceFactorFailure.busy => '正在进行指纹授权，请稍后再试',
    DeviceFactorFailure.rejected => '设备保护材料不匹配或已损坏',
    DeviceFactorFailure.failed => '指纹保护失败，请使用密码',
  };
}

class DeviceFactorContext {
  DeviceFactorContext({required this.reference, required Uint8List aad})
    : _aad = Uint8List.fromList(aad) {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(reference) ||
        aad.isEmpty ||
        aad.length > 1024) {
      throw const FormatException('设备上下文错误');
    }
  }
  final String reference;
  final Uint8List _aad;
  Uint8List get aad => Uint8List.fromList(_aad);
}

class WrappedDeviceFactor {
  WrappedDeviceFactor({
    required Uint8List nonce,
    required Uint8List cipherText,
    required Uint8List mac,
  }) : _nonce = Uint8List.fromList(nonce),
       _cipherText = Uint8List.fromList(cipherText),
       _mac = Uint8List.fromList(mac) {
    if (nonce.length != 12 || cipherText.length != 32 || mac.length != 16) {
      throw const FormatException('设备封装长度错误');
    }
  }
  final Uint8List _nonce;
  final Uint8List _cipherText;
  final Uint8List _mac;
  Uint8List get nonce => Uint8List.fromList(_nonce);
  Uint8List get cipherText => Uint8List.fromList(_cipherText);
  Uint8List get mac => Uint8List.fromList(_mac);
}

abstract interface class DeviceFactorProtection {
  Future<DeviceFactorCapability> capability();
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  );
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor wrapped,
  );
  Future<void> deleteFactor(String reference);
  Future<void> cancel();
}
