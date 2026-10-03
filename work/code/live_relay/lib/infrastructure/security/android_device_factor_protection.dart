import 'dart:io';

import 'package:flutter/services.dart';

import '../../core/ports/device_factor_protection.dart';

class AndroidDeviceFactorProtection implements DeviceFactorProtection {
  AndroidDeviceFactorProtection({MethodChannel? channel, bool? isAndroid})
    : _channel =
          channel ?? const MethodChannel('app.liverelay/device-factor-v1'),
      _isAndroid = isAndroid ?? Platform.isAndroid;

  final MethodChannel _channel;
  final bool _isAndroid;

  @override
  Future<DeviceFactorCapability> capability() async {
    if (!_isAndroid) {
      return const DeviceFactorCapability(
        available: false,
        reason: '当前平台尚未支持设备指纹保护',
      );
    }
    try {
      final status = await _channel.invokeMethod<String>('capability');
      return DeviceFactorCapability(
        available: status == 'available',
        strongBiometricOnly: status == 'available',
        perOperationAuthorization: status == 'available',
        invalidatedByEnrollment: status == 'available',
        reason: status == 'available' ? '每次操作需要强生物识别授权' : '请先在系统中设置强生物识别',
      );
    } on Object {
      return const DeviceFactorCapability(
        available: false,
        reason: '设备指纹保护暂不可用',
      );
    }
  }

  Map<String, Object> _context(DeviceFactorContext context) => {
    'reference': context.reference,
    'aad': context.aad,
  };

  Future<T?> _invoke<T>(String method, [Map<String, Object>? args]) async {
    if (!_isAndroid) {
      throw const DeviceFactorException(DeviceFactorFailure.unavailable);
    }
    try {
      return await _channel.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      final failure = DeviceFactorFailure.values
          .where((f) => f.name == e.code)
          .firstOrNull;
      throw DeviceFactorException(failure ?? DeviceFactorFailure.failed);
    } on MissingPluginException {
      throw const DeviceFactorException(DeviceFactorFailure.unavailable);
    }
  }

  @override
  Future<WrappedDeviceFactor> protectFactor(
    DeviceFactorContext context,
    Uint8List share,
  ) async {
    if (share.length != 32) throw const FormatException('设备份额长度错误');
    final copy = Uint8List.fromList(share);
    try {
      final result = await _invoke<Map>('protect', {
        ..._context(context),
        'share': copy,
      });
      return WrappedDeviceFactor(
        nonce: result!['nonce'] as Uint8List,
        cipherText: result['cipherText'] as Uint8List,
        mac: result['mac'] as Uint8List,
      );
    } finally {
      copy.fillRange(0, copy.length, 0);
    }
  }

  @override
  Future<Uint8List> unprotectFactor(
    DeviceFactorContext context,
    WrappedDeviceFactor wrapped,
  ) async {
    final clear = await _invoke<Uint8List>('unprotect', {
      ..._context(context),
      'nonce': wrapped.nonce,
      'cipherText': wrapped.cipherText,
      'mac': wrapped.mac,
    });
    if (clear == null || clear.length != 32) {
      clear?.fillRange(0, clear.length, 0);
      throw const DeviceFactorException(DeviceFactorFailure.rejected);
    }
    return clear;
  }

  @override
  Future<void> deleteFactor(String reference) async {
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(reference)) {
      throw const FormatException('设备引用错误');
    }
    await _invoke<void>('delete', {'reference': reference});
  }

  @override
  Future<void> cancel() async {
    if (_isAndroid) await _invoke<void>('cancel');
  }
}
