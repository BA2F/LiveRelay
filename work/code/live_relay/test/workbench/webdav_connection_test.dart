import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/application/transfer/webdav_connection_service.dart';
import 'package:live_relay/core/ports/webdav_connection_repository.dart';
import 'package:live_relay/core/transfer/webdav_connection.dart';
import 'package:live_relay/infrastructure/transfer/webdav_connection_store.dart';

class CountingRepository implements WebDavConnectionRepository {
  WebDavConnection? stored;
  int reads = 0, writes = 0, clears = 0;
  @override
  Future<WebDavConnection?> read() async {
    reads++;
    return stored;
  }

  @override
  Future<void> write(WebDavConnection connection) async {
    writes++;
    stored = connection;
  }

  @override
  Future<void> clear() async {
    clears++;
    stored = null;
  }
}

void main() {
  test('connection model validates urls and credentials', () {
    expect(
      WebDavConnection.validationError(
        url: 'drive.example.com/alice',
        username: 'alice',
        password: 'x',
      ),
      isNotNull,
    );
    expect(
      WebDavConnection.validationError(
        url: 'ftp://drive.example.com',
        username: 'alice',
        password: 'x',
      ),
      isNotNull,
    );
    expect(
      WebDavConnection.validationError(
        url: 'https://drive.example.com/alice/',
        username: ' ',
        password: 'x',
      ),
      isNotNull,
    );
    expect(
      WebDavConnection.validationError(
        url: 'https://drive.example.com/alice/',
        username: 'alice',
        password: '',
      ),
      isNotNull,
    );
    final parsed = WebDavConnection.parse(
      url: ' https://drive.example.com/alice/ ',
      username: ' alice ',
      password: 'pass',
    );
    expect(parsed, isNotNull);
    expect(parsed!.baseUrl.toString(), 'https://drive.example.com/alice/');
    expect(parsed.username, 'alice');
    expect(parsed.describe, 'drive.example.com/alice/ · alice');
    final restored = WebDavConnection.fromJson(parsed.toJson());
    expect(restored!.baseUrl, parsed.baseUrl);
    expect(restored.password, 'pass');
    expect(WebDavConnection.fromJson(<String, Object>{'url': 'nope'}), isNull);
  });

  test('store round trips through secure storage and rejects corrupt records',
      () async {
    FlutterSecureStorage.setMockInitialValues({});
    final store = WebDavConnectionStore();
    expect(await store.read(), isNull);
    final connection = WebDavConnection.parse(
      url: 'http://192.168.1.10:3923/',
      username: 'owner',
      password: 'secret',
    )!;
    await store.write(connection);
    final restored = await store.read();
    expect(restored!.baseUrl, connection.baseUrl);
    expect(restored.username, 'owner');
    expect(restored.password, 'secret');
    await store.clear();
    expect(await store.read(), isNull);

    FlutterSecureStorage.setMockInitialValues({
      'liferelay.webdav.connection.v1': jsonEncode({
        'version': 2,
        'connection': connection.toJson(),
      }),
    });
    await expectLater(store.read(), throwsFormatException);
    FlutterSecureStorage.setMockInitialValues({
      'liferelay.webdav.connection.v1': 'not-json',
    });
    await expectLater(store.read(), throwsFormatException);
  });

  test('service caches the connection and writes through to storage', () async {
    final repository = CountingRepository();
    final service = WebDavConnectionService(repository);
    expect(await service.current(), isNull);
    expect(repository.reads, 1);
    await service.current();
    expect(repository.reads, 1, reason: 'cached after the first load');

    final connection = WebDavConnection.parse(
      url: 'https://drive.example.com/alice/',
      username: 'alice',
      password: 'pass',
    )!;
    await service.save(connection);
    expect(repository.writes, 1);
    expect((await service.current())!.username, 'alice');
    await service.clear();
    expect(repository.clears, 1);
    expect(await service.current(), isNull);
  });
}
