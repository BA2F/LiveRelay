import 'dart:convert';
import 'dart:typed_data';

class PcmWave {
  static Float32List decode(Uint8List bytes) {
    if (bytes.length < 44 ||
        bytes.length > 2 * 1024 * 1024 ||
        ascii.decode(bytes.sublist(0, 4), allowInvalid: true) != 'RIFF' ||
        ascii.decode(bytes.sublist(8, 12), allowInvalid: true) != 'WAVE') {
      throw const FormatException('请使用最长 60 秒的 16 kHz 单声道 PCM WAV');
    }
    final view = ByteData.sublistView(bytes);
    var validFormat = false;
    Uint8List? audio;
    for (var p = 12; p + 8 <= bytes.length;) {
      final name = ascii.decode(bytes.sublist(p, p + 4), allowInvalid: true);
      final size = view.getUint32(p + 4, Endian.little);
      final start = p + 8;
      if (start + size > bytes.length) throw const FormatException('WAV 文件不完整');
      if (name == 'fmt ') {
        if (validFormat ||
            size < 16 ||
            view.getUint16(start, Endian.little) != 1 ||
            view.getUint16(start + 2, Endian.little) != 1 ||
            view.getUint32(start + 4, Endian.little) != 16000 ||
            view.getUint16(start + 12, Endian.little) != 2 ||
            view.getUint16(start + 14, Endian.little) != 16) {
          throw const FormatException('需要 16 kHz 单声道 PCM16 WAV');
        }
        validFormat = true;
      } else if (name == 'data') {
        if (audio != null) throw const FormatException('WAV 数据块重复');
        audio = Uint8List.sublistView(bytes, start, start + size);
      }
      p = start + size + (size % 2);
    }
    if (!validFormat ||
        audio == null ||
        audio.isEmpty ||
        audio.length.isOdd ||
        audio.length > 16000 * 2 * 60) {
      throw const FormatException('录音需为 60 秒以内的 PCM16 WAV');
    }
    final data = ByteData.sublistView(audio);
    return Float32List.fromList(
      List.generate(
        audio.length ~/ 2,
        (i) => data.getInt16(i * 2, Endian.little) / 32768,
      ),
    );
  }
}
