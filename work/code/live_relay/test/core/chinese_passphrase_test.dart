import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/security/chinese_passphrase.dart';

void main() {
  late ChinesePassphraseCodec codec;

  setUp(() {
    final source = List.generate(
      1200,
      (index) => 'pin$index 词$index',
    ).join('\n');
    codec = ChinesePassphraseCodec.parse(source);
  });

  test('generates unique words with measured entropy', () {
    final phrase = codec.generate(count: 6, random: Random(42));

    expect(phrase.words, hasLength(6));
    expect(phrase.words.map((word) => word.pinyin).toSet(), hasLength(6));
    expect(phrase.entropyBits, greaterThan(60));
  });

  test('canonicalizes exact Chinese words and pinyin to the same value', () {
    final phrase = codec.generate(count: 4, random: Random(7));

    expect(codec.canonicalize(phrase.chinese, wordCount: 4), phrase.canonical);
    expect(
      codec.canonicalize(phrase.pinyin.toUpperCase(), wordCount: 4),
      phrase.canonical,
    );
    expect(
      codec.canonicalize(
        phrase.words.map((word) => word.hanzi).join(),
        wordCount: 4,
      ),
      phrase.canonical,
    );
  });

  test('removes ambiguous pinyin and display words', () {
    final base = List.generate(1100, (index) => 'p$index 字$index');
    final parsed = ChinesePassphraseCodec.parse(
      [...base, 'same 甲', 'same 乙', 'unique 字1'].join('\n'),
    );

    expect(parsed.words.any((word) => word.pinyin == 'same'), isFalse);
    expect(parsed.words.any((word) => word.hanzi == '字1'), isFalse);
  });
}
