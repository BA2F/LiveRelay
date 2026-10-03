import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/ports/device_factor_protection.dart';
import 'package:live_relay/infrastructure/security/android_device_factor_protection.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fictional-device-factor-tests');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final context = DeviceFactorContext(
    reference: '1' * 32,
    aad: Uint8List.fromList([1, 2, 3]),
  );
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'non-Android reports unsupported and never calls any device method',
    () async {
      messenger.setMockMethodCallHandler(
        channel,
        (_) async => throw StateError('unexpected call'),
      );
      final adapter = AndroidDeviceFactorProtection(
        channel: channel,
        isAndroid: false,
      );
      expect((await adapter.capability()).available, false);
      await expectLater(
        adapter.protectFactor(context, Uint8List(32)),
        throwsA(isA<DeviceFactorException>()),
      );
    },
  );

  test('per-operation bridge preserves cancellation and invalidation, without another read', () async {
    var calls = 0;
    var code = 'cancelled';
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls++;
      expect(call.method, 'unprotect');
      expect((call.arguments as Map)['reference'], context.reference);
      throw PlatformException(code: code);
    });
    final adapter = AndroidDeviceFactorProtection(
      channel: channel,
      isAndroid: true,
    );
    final wrapped = WrappedDeviceFactor(
      nonce: Uint8List(12),
      cipherText: Uint8List(32),
      mac: Uint8List(16),
    );
    for (final failure in [
      DeviceFactorFailure.cancelled,
      DeviceFactorFailure.invalidated,
    ]) {
      code = failure.name;
      await expectLater(
        adapter.unprotectFactor(context, wrapped),
        throwsA(
          isA<DeviceFactorException>().having(
            (e) => e.failure,
            'failure',
            failure,
          ),
        ),
      );
    }
    expect(calls, 2);
  });

  test('malformed native secret cannot be returned to the vault', () async {
    final native = Uint8List.fromList([1, 2, 3]);
    messenger.setMockMethodCallHandler(channel, (_) async => native);
    final adapter = AndroidDeviceFactorProtection(
      channel: channel,
      isAndroid: true,
    );
    await expectLater(
      adapter.unprotectFactor(
        context,
        WrappedDeviceFactor(
          nonce: Uint8List(12),
          cipherText: Uint8List(32),
          mac: Uint8List(16),
        ),
      ),
      throwsA(
        isA<DeviceFactorException>().having(
          (e) => e.failure,
          'failure',
          DeviceFactorFailure.rejected,
        ),
      ),
    );
  });
}
