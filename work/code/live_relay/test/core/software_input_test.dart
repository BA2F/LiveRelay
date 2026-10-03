import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/password_generator.dart';
import 'package:live_relay/infrastructure/speech/pcm_wave.dart';

Uint8List wave({int frames = 2, int channels = 1, int encoding = 1}) {
  final bytes = Uint8List(44 + frames * 2);
  final data = ByteData.sublistView(bytes);
  bytes.setRange(0, 4, ascii.encode('RIFF'));
  bytes.setRange(8, 12, ascii.encode('WAVE'));
  bytes.setRange(12, 16, ascii.encode('fmt '));
  bytes.setRange(36, 40, ascii.encode('data'));
  data.setUint32(4, bytes.length - 8, Endian.little);
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, encoding, Endian.little);
  data.setUint16(22, channels, Endian.little);
  data.setUint32(24, 16000, Endian.little);
  data.setUint32(28, 32000, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  data.setUint32(40, frames * 2, Endian.little);
  data.setInt16(44, -32768, Endian.little);
  data.setInt16(46, 16384, Endian.little);
  return bytes;
}

void main() {
  test('generated passwords satisfy selected classes and bounds', () {
    final password = PasswordGenerator.generate();
    expect(password, hasLength(20));
    for (final pattern in [r'[A-Z]', r'[a-z]', r'[2-9]', r'[!@#%&*+\-_=?:]']) {
      expect(RegExp(pattern).hasMatch(password), isTrue);
    }
    final digits = PasswordGenerator.generate(
      length: 8,
      uppercase: false,
      lowercase: false,
      symbols: false,
    );
    expect(RegExp(r'^[2-9]{8}$').hasMatch(digits), isTrue);
    expect(() => PasswordGenerator.generate(length: 7), throwsFormatException);
    expect(
      () => PasswordGenerator.generate(
        uppercase: false,
        lowercase: false,
        digits: false,
        symbols: false,
      ),
      throwsFormatException,
    );
  });
  test('PCM16 WAV yields normalized samples', () {
    expect(PcmWave.decode(wave()), [-1.0, 0.5]);
  });
  test('compressed, stereo, truncated and overlong audio is rejected', () {
    for (final bytes in [
      wave(encoding: 3),
      wave(channels: 2),
      wave().sublist(0, 44),
      wave(frames: 16000 * 60 + 1),
    ]) {
      expect(
        () => PcmWave.decode(Uint8List.fromList(bytes)),
        throwsFormatException,
      );
    }
  });
}
