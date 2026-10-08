import 'dart:convert';
import 'dart:io';

import '../../core/ports/device_preferences_repository.dart';

class FileDevicePreferencesRepository implements DevicePreferencesRepository {
  FileDevicePreferencesRepository(this.file);
  final File? file;
  @override
  Future<Map<String, Object?>?> read() async {
    final source = file;
    if (source == null || !await source.exists()) return null;
    return Map<String, Object?>.from(
      jsonDecode(await source.readAsString()) as Map,
    );
  }

  @override
  Future<void> write(Map<String, Object?> data) async {
    final target = file;
    if (target == null) return;
    await target.parent.create(recursive: true);
    final temporary = File('${target.path}.tmp');
    try {
      await temporary.writeAsString(jsonEncode(data), flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}
