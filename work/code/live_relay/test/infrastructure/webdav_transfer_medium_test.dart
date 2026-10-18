import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/ports/transfer_medium.dart';
import 'package:live_relay/infrastructure/transfer/webdav_transfer_medium.dart';

/// Minimal in-memory WebDAV server for exercising the client without any
/// external dependency; mirrors the subset the deployed copyparty serves.
class FakeDavServer {
  FakeDavServer({this.obeyRange = true});
  final bool obeyRange;
  final files = <String, List<int>>{};
  final requests = <String>[];
  static const expectedAuth =
      'Basic dXNlcjpwYXNz'; // user:pass

  late final HttpServer _server;
  late final Uri url;

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    url = Uri.parse('http://127.0.0.1:${_server.port}/');
    _server.listen(_handle);
  }

  Future<void> stop() => _server.close(force: true);

  String _xmlListing(String pathPrefix) {
    final buffer = StringBuffer(
      '<?xml version="1.0" encoding="utf-8"?>\n<D:multistatus xmlns:D="DAV:">\n',
    );
    buffer.write(
      '<D:response><D:href>$pathPrefix</D:href>'
      '<D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype>'
      '</D:prop></D:propstat></D:response>\n',
    );
    // A subdirectory entry must be ignored by the client.
    buffer.write(
      '<D:response><D:href>${pathPrefix}sub/</D:href>'
      '<D:propstat><D:prop><D:resourcetype><D:collection/></D:resourcetype>'
      '</D:prop></D:propstat></D:response>\n',
    );
    for (final entry in files.entries) {
      buffer.write(
        '<D:response><D:href>$pathPrefix${Uri.encodeComponent(entry.key)}</D:href>'
        '<D:propstat><D:prop><D:resourcetype/>'
        '<D:getcontentlength>${entry.value.length}</D:getcontentlength>'
        '</D:prop></D:propstat></D:response>\n',
      );
    }
    buffer.write('</D:multistatus>');
    return buffer.toString();
  }

  Future<void> _handle(HttpRequest request) async {
    requests.add('${request.method} ${request.uri.path}');
    if (request.headers.value('authorization') != expectedAuth) {
      request.response.statusCode = 403;
      await request.response.close();
      return;
    }
    final name = request.uri.pathSegments.isEmpty
        ? ''
        : request.uri.pathSegments.last;
    switch (request.method) {
      case 'PROPFIND':
        request.response.statusCode = 207;
        request.response.headers.contentType = ContentType(
          'application',
          'xml',
        );
        request.response.write(_xmlListing(request.uri.path));
      case 'GET':
        final bytes = files[name];
        if (bytes == null) {
          request.response.statusCode = 404;
        } else {
          final range = request.headers.value('range');
          if (obeyRange && range != null) {
            final parts = RegExp(r'bytes=(\d+)-(\d+)').firstMatch(range)!;
            final start = int.parse(parts.group(1)!);
            final end = int.parse(parts.group(2)!);
            final slice = bytes.sublist(
              start,
              end + 1 > bytes.length ? bytes.length : end + 1,
            );
            request.response.statusCode = 206;
            request.response.add(slice);
          } else {
            request.response.statusCode = 200;
            request.response.add(bytes);
          }
        }
      case 'PUT':
        final body = await request.fold<List<int>>(
          <int>[],
          (buffer, chunk) => buffer..addAll(chunk),
        );
        files[name] = body;
        request.response.statusCode = 201;
      case 'MOVE':
        final destination = request.headers.value('destination');
        final target = Uri.parse(destination!).pathSegments.last;
        final bytes = files.remove(name);
        if (bytes == null) {
          request.response.statusCode = 404;
        } else {
          files[target] = bytes;
          request.response.statusCode = 201;
        }
      case 'DELETE':
        files.remove(name);
        request.response.statusCode = 204;
      default:
        request.response.statusCode = 405;
    }
    await request.response.close();
  }
}

WebDavTransferMedium mediumFor(FakeDavServer server, {String? baseUrl}) =>
    WebDavTransferMedium(
      baseUrl: Uri.parse(baseUrl ?? server.url.toString()),
      username: 'user',
      password: 'pass',
    );

void main() {
  test('lists files with lengths and skips the collection and subdirectories',
      () async {
    final server = FakeDavServer();
    await server.start();
    addTearDown(server.stop);
    server.files['LiveRelay-aaaaaaaa-database.lvault'] = List.filled(120, 7);
    server.files['LiveRelay-aaaaaaaa-originals-0001.lvault'] =
        List.filled(2048, 9);

    final medium = mediumFor(server);
    final entries = await medium.list();
    expect(entries.map((e) => e.name), [
      'LiveRelay-aaaaaaaa-database.lvault',
      'LiveRelay-aaaaaaaa-originals-0001.lvault',
    ]);
    expect(entries.first.length, 120);
    expect(entries.last.length, 2048);
  });

  test('reads prefixes through range requests, with a full-read fallback',
      () async {
    final server = FakeDavServer();
    await server.start();
    addTearDown(server.stop);
    server.files['pack.lvault'] = List.generate(4096, (i) => i % 251);

    final medium = mediumFor(server);
    final prefix = await medium.readPrefix('pack.lvault', 64);
    expect(prefix.length, 64);
    expect(prefix, server.files['pack.lvault']!.sublist(0, 64));
    expect(await medium.read('pack.lvault'), server.files['pack.lvault']);
    await expectLater(medium.read('missing.lvault'), throwsA(isA<TransferMediumException>()));

    final plain = FakeDavServer(obeyRange: false);
    await plain.start();
    addTearDown(plain.stop);
    plain.files['pack.lvault'] = List.generate(1000, (i) => i % 97);
    final fallback = await mediumFor(plain).readPrefix('pack.lvault', 32);
    expect(fallback.length, 32);
    expect(fallback, plain.files['pack.lvault']!.sublist(0, 32));
  });

  test('writes atomically through PUT and an overwriting MOVE', () async {
    final server = FakeDavServer();
    await server.start();
    addTearDown(server.stop);
    server.files['final.lvault'] = utf8.encode('old-target-content');

    final medium = mediumFor(server);
    await medium.writeAtomic(
      'LiveRelay-aaaaaaaa-database.lvault',
      Uint8List.fromList(utf8.encode('first version')),
    );
    expect(
      utf8.decode(server.files['LiveRelay-aaaaaaaa-database.lvault']!),
      'first version',
    );
    expect(
      server.files.keys.where((name) => name.endsWith('.tmp')),
      isEmpty,
      reason: 'the temporary name must not survive the move',
    );

    await medium.writeAtomic(
      'LiveRelay-aaaaaaaa-database.lvault',
      Uint8List.fromList(utf8.encode('second version, longer')),
    );
    expect(
      utf8.decode(server.files['LiveRelay-aaaaaaaa-database.lvault']!),
      'second version, longer',
    );

    await medium.writeAtomic(
      'final.lvault',
      Uint8List.fromList(utf8.encode('replaced')),
    );
    expect(utf8.decode(server.files['final.lvault']!), 'replaced');
    expect(
      server.requests,
      contains('PUT /LiveRelay-aaaaaaaa-database.lvault.tmp'),
    );
    expect(server.requests, contains('MOVE /LiveRelay-aaaaaaaa-database.lvault.tmp'));
  });

  test('maps auth failures, missing files and dead links to clear messages',
      () async {
    final server = FakeDavServer();
    await server.start();
    addTearDown(server.stop);
    final bad = WebDavTransferMedium(
      baseUrl: server.url,
      username: 'user',
      password: 'wrong',
    );
    await expectLater(
      bad.list(),
      throwsA(
        isA<TransferMediumException>().having(
          (e) => e.message,
          'message',
          contains('拒绝访问'),
        ),
      ),
    );

    // A port with nothing listening: connection failure, not a crash. Some
    // Windows hosts need about two seconds before the refused loopback
    // connection reports SocketException, so the budget has to stay above
    // that; the case still has to surface a connection failure rather than
    // being reported as a timeout.
    final dead = WebDavTransferMedium(
      baseUrl: Uri.parse('http://127.0.0.1:1/'),
      username: 'user',
      password: 'pass',
      timeout: const Duration(seconds: 15),
    );
    await expectLater(
      dead.list(),
      throwsA(
        isA<TransferMediumException>().having(
          (e) => e.message,
          'message',
          contains('无法连接云端'),
        ),
      ),
    );
  });

  test('normalizes base urls and reads through sub paths', () async {
    final server = FakeDavServer();
    await server.start();
    addTearDown(server.stop);
    server.files['x.lvault'] = List.filled(10, 1);
    final medium = mediumFor(
      server,
      baseUrl: '${server.url}liverelay',
    );
    expect(medium.label, '云端 127.0.0.1/liverelay/');
    expect(await medium.read('x.lvault'), List.filled(10, 1));
  });
}
