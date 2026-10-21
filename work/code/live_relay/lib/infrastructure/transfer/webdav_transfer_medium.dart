import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../core/ports/transfer_medium.dart';

/// A transfer medium that speaks a plain WebDAV subset over HTTP(S):
/// PROPFIND for listings, ranged GET for prefix reads, PUT plus an
/// overwriting MOVE for atomic writes. Works against any standard WebDAV
/// server (the deployed copyparty service included); no server-specific
/// extensions are used, so byte-level upload resume is not required — the
/// volume layout already reduces retries to single files.
class WebDavTransferMedium implements TransferMedium {
  WebDavTransferMedium({
    required Uri baseUrl,
    required this.username,
    required this.password,
    http.Client? client,
    this.timeout = const Duration(seconds: 60),
  }) : _base = baseUrl.path.endsWith('/') || baseUrl.path.isEmpty
           ? baseUrl
           : baseUrl.replace(path: '${baseUrl.path}/'),
       _client = client ?? http.Client();

  final Uri _base;
  final String username;
  final String password;
  final http.Client _client;
  final Duration timeout;

  static const _maximumEntries = 10000;

  @override
  String get label {
    final path = _base.path == '/' ? '' : _base.path;
    return '云端 ${_base.host}$path';
  }

  Map<String, String> get _auth => {
    'Authorization':
        'Basic ${base64Encode(utf8.encode('$username:$password'))}',
  };

  Uri _url(String name) {
    if (name.isEmpty || name.contains('/') || name.contains('\\')) {
      throw ArgumentError('非法介质文件名');
    }
    return _base.resolve(Uri.encodeComponent(name));
  }

  Future<http.Response> _request(
    String method,
    Uri url, {
    Map<String, String> headers = const {},
    List<int>? body,
  }) async {
    final request = http.Request(method, url);
    request.headers.addAll(_auth);
    request.headers.addAll(headers);
    if (body != null) request.bodyBytes = body;
    try {
      final streamed = await _client.send(request).timeout(timeout);
      return await http.Response.fromStream(streamed).timeout(timeout);
    } on TimeoutException {
      throw const TransferMediumException('云端超时：检查网址与网络后重试');
    } on SocketException catch (error) {
      throw TransferMediumException('无法连接云端（${error.message}）');
    } on http.ClientException catch (error) {
      throw TransferMediumException('无法连接云端（${error.message}）');
    }
  }

  Never _failure(String action, int status) {
    if (status == 401 || status == 403) {
      throw const TransferMediumException('云端拒绝访问：检查网址、账号密码与目录权限');
    }
    throw TransferMediumException('$action失败（HTTP $status）');
  }

  bool _ok(int status) => status >= 200 && status < 300;

  @override
  Future<List<MediumEntry>> list() async {
    final response = await _request(
      'PROPFIND',
      _base,
      headers: {'Depth': '1', 'Content-Type': 'application/xml; charset=utf-8'},
      body: utf8.encode(
        '<?xml version="1.0" encoding="utf-8"?>'
        '<D:propfind xmlns:D="DAV:"><D:prop>'
        '<D:resourcetype/><D:getcontentlength/>'
        '</D:prop></D:propfind>',
      ),
    );
    if (response.statusCode != 207) _failure('读取云端目录', response.statusCode);
    final body = utf8.decode(response.bodyBytes, allowMalformed: true);
    final baseSegments = _base.pathSegments.where((s) => s.isNotEmpty).toList();
    final entries = <MediumEntry>[];
    final blocks = RegExp(
      r'<(?:[A-Za-z0-9._-]+:)?response(?:\s[^>]*)?>(.*?)'
      r'</(?:[A-Za-z0-9._-]+:)?response>',
      dotAll: true,
    ).allMatches(body);
    for (final block in blocks) {
      final responseBody = block.group(1) ?? '';
      if (RegExp(r'<(?:[A-Za-z0-9._-]+:)?collection\b')
          .hasMatch(responseBody)) {
        continue;
      }
      final href = _tagText(responseBody, 'href');
      if (href == null) continue;
      final segments = Uri.parse(href).pathSegments
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.length != baseSegments.length + 1) continue;
      entries.add(
        MediumEntry(
          // pathSegments arrives percent-decoded.
          name: segments.last,
          length:
              int.tryParse(_tagText(responseBody, 'getcontentlength') ?? '') ??
              0,
        ),
      );
      if (entries.length > _maximumEntries) {
        throw const TransferMediumException('云端目录条目异常，已停止读取');
      }
    }
    entries.sort((a, b) => a.name.compareTo(b.name));
    return entries;
  }

  String? _tagText(String xml, String tag) {
    final match = RegExp(
      '<(?:[A-Za-z0-9._-]+:)?$tag(?:\\s[^>]*)?>([^<]*)'
      '</(?:[A-Za-z0-9._-]+:)?$tag>',
    ).firstMatch(xml);
    return match?.group(1);
  }

  @override
  Future<Uint8List> readPrefix(String name, int maxBytes) async {
    final response = await _request(
      'GET',
      _url(name),
      headers: {'Range': 'bytes=0-${maxBytes - 1}'},
    );
    if (response.statusCode == 404) {
      throw const TransferMediumException('云端没有这个文件', notFound: true);
    }
    if (!_ok(response.statusCode) && response.statusCode != 206) {
      _failure('读取云端文件', response.statusCode);
    }
    final bytes = response.bodyBytes;
    return bytes.length > maxBytes
        ? Uint8List.sublistView(bytes, 0, maxBytes)
        : bytes;
  }

  @override
  Future<Uint8List> read(String name) async {
    final response = await _request('GET', _url(name));
    if (response.statusCode == 404) {
      throw const TransferMediumException('云端没有这个文件', notFound: true);
    }
    if (!_ok(response.statusCode)) _failure('读取云端文件', response.statusCode);
    return response.bodyBytes;
  }

  @override
  Future<void> writeAtomic(String name, Uint8List bytes) async {
    final temporary = '$name.tmp';
    final put = await _request('PUT', _url(temporary), body: bytes);
    if (!_ok(put.statusCode)) {
      await _deleteQuietly(temporary);
      _failure('写入云端文件', put.statusCode);
    }
    final move = await _request(
      'MOVE',
      _url(temporary),
      headers: {'Destination': _url(name).toString(), 'Overwrite': 'T'},
    );
    if (!_ok(move.statusCode)) {
      await _deleteQuietly(temporary);
      _failure('写入云端文件', move.statusCode);
    }
  }

  Future<void> _deleteQuietly(String name) async {
    try {
      await _request('DELETE', _url(name));
    } on Object {
      // A leftover .tmp never matches the package naming rules.
    }
  }

  @override
  Future<void> delete(String name) async {
    final response = await _request('DELETE', _url(name));
    if (response.statusCode == 404) return;
    if (!_ok(response.statusCode)) _failure('删除云端文件', response.statusCode);
  }

  void close() => _client.close();
}
