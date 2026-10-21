import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as path;

import '../../core/ports/transfer_medium.dart';
import '../../core/storage/file_commit.dart';

/// A user-chosen directory acting as the transfer medium: a USB stick, a
/// mounted LAN share, or a mounted WebDAV drive all look the same here.
class DirectoryTransferMedium implements TransferMedium {
  DirectoryTransferMedium(this.directory);

  final Directory directory;

  /// True when dart:io can actually write into the directory; a SAF tree path
  /// handed back as a plain string usually cannot, and the callers then fall
  /// back to the file-set medium.
  static Future<bool> probeWritable(Directory directory) async {
    try {
      if (!await directory.exists()) return false;
      final probe = File('${directory.path}/.liverelay-write-probe');
      await probe.writeAsBytes(const <int>[0], flush: true);
      await probe.delete();
      return true;
    } on Object {
      return false;
    }
  }

  @override
  String get label => directory.path;

  @override
  Future<List<MediumEntry>> list() async {
    final entries = <MediumEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) continue;
      final name = path.basename(entity.path);
      if (name.endsWith('.tmp')) continue;
      entries.add(MediumEntry(name: name, length: await entity.length()));
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  File _file(String name) {
    if (name.isEmpty ||
        name.contains('/') ||
        name.contains('\\') ||
        name.endsWith('.tmp')) {
      throw ArgumentError('非法介质文件名');
    }
    return File(path.join(directory.path, name));
  }

  @override
  Future<Uint8List> read(String name) => _file(name).readAsBytes();

  @override
  Future<Uint8List> readPrefix(String name, int maxBytes) async {
    final file = _file(name);
    final handle = await file.open();
    try {
      final length = await file.length();
      return await handle.read(length < maxBytes ? length : maxBytes);
    } finally {
      await handle.close();
    }
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    final file = _file(name);
    await file.parent.create(recursive: true);
    final temporary = File('${file.path}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await commitFile(temporary, file);
    } on Object {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  @override
  Future<void> delete(String name) async {
    final file = _file(name);
    if (await file.exists()) await file.delete();
  }
}
