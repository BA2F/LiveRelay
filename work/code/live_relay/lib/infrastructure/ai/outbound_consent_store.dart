import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/ai/outbound_consent.dart';
import '../../core/ports/outbound_consent_repository.dart';

/// 设备本地的外发授权记录，与 AI 服务配置同处一份设备存储。
/// 记录不是秘密，但读取失败时按未授权处理：宁可多问一次，不静默放行。
class OutboundConsentStore implements OutboundConsentRepository {
  OutboundConsentStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(
              storageNamespace: 'liverelay_outbound_consent_v1',
            ),
          );
  final FlutterSecureStorage _storage;
  static const _key = 'liverelay.outbound.consent.v1';
  static const _maxDestinations = 64;

  @override
  Future<Map<String, Set<OutboundKind>>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return const {};
    if (raw.length > 64 * 1024) throw const FormatException('外发授权记录过大');
    final data = jsonDecode(raw);
    if (data is! Map ||
        data['version'] != 1 ||
        data['grants'] is! Map ||
        (data['grants'] as Map).length > _maxDestinations) {
      throw const FormatException('外发授权记录无法读取，原记录已保留');
    }
    final grants = <String, Set<OutboundKind>>{};
    for (final entry in (data['grants'] as Map).entries) {
      final id = entry.key;
      final kinds = entry.value;
      if (id is! String ||
          id.isEmpty ||
          id.length > 256 ||
          kinds is! List ||
          kinds.isEmpty) {
        throw const FormatException('外发授权记录无法读取，原记录已保留');
      }
      final parsed = <OutboundKind>{};
      for (final value in kinds) {
        final kind = value is String ? OutboundKind.fromWire(value) : null;
        if (kind == null) {
          throw const FormatException('外发授权记录无法读取，原记录已保留');
        }
        parsed.add(kind);
      }
      grants[id] = parsed;
    }
    return grants;
  }

  @override
  Future<void> write(Map<String, Set<OutboundKind>> grants) {
    if (grants.length > _maxDestinations) {
      throw const FormatException('外发授权记录过大');
    }
    return _storage.write(
      key: _key,
      value: jsonEncode({
        'version': 1,
        'grants': {
          for (final entry in grants.entries)
            entry.key: [
              for (final kind in OutboundKind.values)
                if (entry.value.contains(kind)) kind.wireName,
            ],
        },
      }),
    );
  }
}
