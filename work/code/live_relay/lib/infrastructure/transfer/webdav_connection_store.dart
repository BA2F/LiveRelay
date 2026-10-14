import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/ports/webdav_connection_repository.dart';
import '../../core/transfer/webdav_connection.dart';

/// The cloud drive connection lives in device secure storage next to the AI
/// credentials: it is this device's access to a server, not vault content,
/// so it neither enters nor travels with the encrypted vault.
class WebDavConnectionStore implements WebDavConnectionRepository {
  WebDavConnectionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'liverelay_webdav_connection_v1',
            ),
          );

  final FlutterSecureStorage _storage;
  static const _key = 'liferelay.webdav.connection.v1';

  @override
  Future<WebDavConnection?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    if (raw.length > 8 * 1024) {
      throw const FormatException('云端连接配置异常，原记录已保留');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on Object {
      throw const FormatException('云端连接配置无法读取，原记录已保留');
    }
    if (decoded is! Map || decoded['version'] != 1) {
      throw const FormatException('云端连接配置无法读取，原记录已保留');
    }
    final connection = WebDavConnection.fromJson(decoded['connection']);
    if (connection == null) {
      throw const FormatException('云端连接配置无法读取，原记录已保留');
    }
    return connection;
  }

  @override
  Future<void> write(WebDavConnection connection) => _storage.write(
    key: _key,
    value: jsonEncode(<String, Object>{
      'version': 1,
      'connection': connection.toJson(),
    }),
  );

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
