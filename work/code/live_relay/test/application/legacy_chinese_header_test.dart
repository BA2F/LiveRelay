import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';
import 'package:live_relay/core/security/header_encoding.dart';

import '../support/session_fakes.dart';

void main() {
  test('independent legacy Chinese header accepts original Chinese input without upgrading', () async {
    final root = await Directory.systemTemp.createTemp('legacy-chinese-');
    addTearDown(() => root.delete(recursive: true));
    final info = jsonDecode(
      await File('test/fixtures/header_v2/vectors.json').readAsString(),
    ) as Map;
    final file = await File('test/fixtures/header_v2/legacy-chinese.json')
        .copy('${root.path}/vault-header.json');
    final original = await file.readAsBytes();
    await File('${root.path}/vault.sqlite')
        .writeAsBytes([1]); // Opaque fixture: injected repository owns opening.
    final codec = ChinesePassphraseCodec.parse(
      await File('assets/wordlists/new-default-pinyin.wordlist').readAsString(),
    );
    final chinese = (info['legacyChinesePassword'] as String)
        .split(' ')
        .map((p) => codec.words.firstWhere((word) => word.pinyin == p).hanzi)
        .join();
    var opens = 0;
    final session = fixtureSession(
      directory: root,
      openRepository: (_, key) async {
        expect(key, HeaderEncoding.decodeBinary(info['masterKey'], 32));
        opens++;
        return SessionRepository();
      },
    );
    try {
      await session.prepare();
      await session.inspect();
      expect(session.header!.usesChinesePassphrase, isTrue);
      expect(session.header!.formatVersion, 1);
      await session.unlockWithPassword(chinese);
      expect(session.isUnlocked, isTrue);
      expect(opens, 1);
      expect(await file.readAsBytes(), original);
    } finally {
      await session.close();
      session.dispose();
    }
  });
}
