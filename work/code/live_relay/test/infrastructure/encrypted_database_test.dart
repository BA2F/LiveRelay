import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/infrastructure/persistence/app_database.dart';
import 'package:live_relay/infrastructure/persistence/sqlite_vault_repository.dart';

void main() {
  test(
    'SQLCipher database rejects the wrong key and hides plaintext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'liverelay-db-test',
      );
      addTearDown(() => directory.delete(recursive: true));
      final key = Uint8List.fromList(
        List<int>.generate(32, (index) => index + 1),
      );

      var database = await AppDatabase.openEncrypted(
        vaultDirectory: directory,
        masterKey: key,
      );
      var repository = SqliteVaultRepository(database);
      await repository.createCard(
        const CardDraft(title: '绝不能出现在磁盘中', content: '敏感测试内容'),
      );
      await repository.close();

      final bytes = await File('${directory.path}/vault.sqlite').readAsBytes();
      expect(String.fromCharCodes(bytes), isNot(contains('绝不能出现在磁盘中')));

      await expectLater(
        AppDatabase.openEncrypted(
          vaultDirectory: directory,
          masterKey: Uint8List(32),
        ),
        throwsA(anything),
      );

      database = await AppDatabase.openEncrypted(
        vaultDirectory: directory,
        masterKey: key,
      );
      repository = SqliteVaultRepository(database);
      expect(await repository.listCards(), hasLength(1));
      await repository.close();
    },
  );
}
