import 'dart:convert';
import 'dart:typed_data';

import 'local_identity.dart';
import '../security/header_encoding.dart';
import '../security/owner_crypto.dart';

/// Signature, scope and disclosure validation, independent of persistence.
class ScopedDelivery {
  static Future<Map<String, Object?>> inspectEnvelope(Uint8List bytes) async {
    if (bytes.length > 180 * 1024 * 1024) throw const FormatException('交接包过大');
    final data = OwnerCrypto.map(jsonDecode(utf8.decode(bytes)), {
      'version',
      'kind',
      'packageId',
      'owner',
      'recipient',
      'scopeEpoch',
      'sequence',
      'createdAt',
      'scopeDigest',
      'box',
      'signature',
    });
    if (data['version'] != 1 ||
        data['kind'] != 'scoped-delivery' ||
        data['scopeEpoch'] != 1 ||
        data['sequence'] is! int ||
        (data['sequence'] as int) < 1 ||
        data['packageId'] is! String ||
        !RegExp(r'^[0-9a-f]{32}$').hasMatch(data['packageId'] as String) ||
        DateTime.tryParse('${data['createdAt']}') == null) {
      throw const FormatException('交接包格式错误');
    }
    final owner = LocalIdentity.validatePublic(data['owner']);
    final unsigned = Map<String, Object?>.from(data)..remove('signature');
    await LocalIdentity.verify(
      owner,
      HeaderEncoding.encode(unsigned),
      data['signature'],
    );
    return data;
  }

  static void validatePayload(Map<String, Object?> payload) {
    final referenced = <String>{};
    final seen = <String>{};
    for (final raw in payload['records'] as List) {
      if (raw is! Map<String, Object?>) throw const FormatException('交接记录格式错误');
      OwnerCrypto.map(raw, {
        'type',
        'id',
        'level',
        'title',
        'body',
        'history',
        'originalIds',
        if (raw.containsKey('secret')) 'secret',
      });
      if (!['card', 'credential'].contains(raw['type']) ||
          raw['id'] is! String ||
          (raw['id'] as String).length > 100 ||
          !seen.add('${raw['type']}/${raw['id']}') ||
          ![
            'existence',
            'summary',
            'full',
            'secret',
            'original',
          ].contains(raw['level']) ||
          raw['title'] is! String ||
          raw['body'] is! String ||
          raw['history'] is! List ||
          (raw['history'] as List).length > 10000 ||
          raw['originalIds'] is! List) {
        throw const FormatException('交接记录格式错误');
      }
      final credential = raw['type'] == 'credential';
      if (raw.containsKey('secret') &&
          (!credential ||
              !['secret', 'original'].contains(raw['level']) ||
              raw['secret'] is! String)) {
        throw const FormatException('交接密码范围错误');
      }
      final history = raw['history'] as List;
      if (history.isNotEmpty &&
          (credential
              ? !['secret', 'original'].contains(raw['level'])
              : !['full', 'secret', 'original'].contains(raw['level']))) {
        throw const FormatException('交接历史范围错误');
      }
      for (final revision in history) {
        final r = OwnerCrypto.map(
          revision,
          credential
              ? {'number', 'title', 'username', 'secret', 'website', 'notes'}
              : {'number', 'title', 'body', 'date'},
        );
        if (r['number'] is! int ||
            (r['number'] as int) < 1 ||
            r.entries.any((e) => e.key != 'number' && e.value is! String)) {
          throw const FormatException('修订格式错误');
        }
      }
      final ids = raw['originalIds'] as List;
      if (ids.isNotEmpty && (credential || raw['level'] != 'original')) {
        throw const FormatException('交接原件范围错误');
      }
      for (final id in ids) {
        if (id is! String || id.length > 100) {
          throw const FormatException('原件标识错误');
        }
        referenced.add(id);
      }
    }
    final originals = payload['originals'] as Map;
    if (originals.length != referenced.length ||
        !referenced.containsAll(originals.keys.cast<String>())) {
      throw const FormatException('原件范围与记录不一致');
    }
    var total = 0;
    for (final raw in originals.values) {
      final original = OwnerCrypto.map(raw, {'name', 'mimeType', 'bytes'});
      if (original['name'] is! String ||
          (original['name'] as String).length > 1000 ||
          original['mimeType'] is! String ||
          original['bytes'] is! String ||
          (original['bytes'] as String).length > 96 * 1024 * 1024) {
        throw const FormatException('原件格式错误');
      }
      final bytes = Uint8List.fromList(
        base64Url.decode(base64Url.normalize(original['bytes'] as String)),
      );
      try {
        total += bytes.length;
        if (total > 64 * 1024 * 1024 ||
            HeaderEncoding.binary(bytes) != original['bytes']) {
          throw const FormatException('原件大小或编码错误');
        }
      } finally {
        OwnerCrypto.wipe(bytes);
      }
    }
  }
}
