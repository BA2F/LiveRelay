import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../core/ports/transfer_medium.dart';

/// One file the user picked from the medium, decoupled from the picker's
/// platform type so the fallback medium stays testable.
class MediumSourceFile {
  const MediumSourceFile({
    required this.name,
    required this.readBytes,
    this.length,
  });

  final String name;
  final int? length;
  final Future<Uint8List> Function() readBytes;
}

/// Fallback medium for devices where the chosen directory cannot be written
/// through dart:io (typically Android SAF tree paths): imports read from a
/// user-picked file set, and every export package is saved through its own
/// system dialog. Coarser than a real directory, but honest — a cancelled
/// save aborts the export with a clear message instead of losing bytes.
class FileSetTransferMedium implements TransferMedium {
  FileSetTransferMedium(
    List<MediumSourceFile> files, {
    Future<bool> Function(String name, Uint8List bytes)? save,
  }) : _files = {for (final file in files) file.name: file},
       _save = save ?? _saveWithPicker;

  final Map<String, MediumSourceFile> _files;
  final Future<bool> Function(String name, Uint8List bytes) _save;

  static Future<bool> _saveWithPicker(String name, Uint8List bytes) async =>
      await FilePicker.saveFile(fileName: name, bytes: bytes) != null;

  @override
  String get label => '已选择的 ${_files.length} 个介质文件';

  @override
  Future<List<MediumEntry>> list() async {
    final entries = <MediumEntry>[];
    for (final file in _files.values) {
      entries.add(
        MediumEntry(
          name: file.name,
          length: file.length ?? (await file.readBytes()).length,
        ),
      );
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  @override
  Future<Uint8List> readPrefix(String name, int maxBytes) async {
    final bytes = await read(name);
    return bytes.length > maxBytes
        ? Uint8List.sublistView(bytes, 0, maxBytes)
        : bytes;
  }

  @override
  Future<Uint8List> read(String name) async {
    final file = _files[name];
    if (file == null) throw StateError('介质上没有文件 $name');
    return file.readBytes();
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    final saved = await _save(name, bytes);
    if (!saved) {
      throw StateError('已取消保存 $name；可稍后重新导出，已保存的文件不会重复生成');
    }
  }

  @override
  Future<void> delete(String name) async {
    _files.remove(name);
  }
}
