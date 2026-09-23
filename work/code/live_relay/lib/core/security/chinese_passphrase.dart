import 'dart:math';

class PassphraseWord {
  const PassphraseWord(this.pinyin, this.hanzi);

  final String pinyin;
  final String hanzi;
}

class ChinesePassphrase {
  const ChinesePassphrase(this.words, this.entropyBits);

  final List<PassphraseWord> words;
  final double entropyBits;

  String get chinese => words.map((word) => word.hanzi).join(' ');
  String get pinyin => words.map((word) => word.pinyin).join(' ');
  String get canonical => pinyin;
}

/// Parses the provided research wordlist and removes every ambiguous pinyin or
/// display word. Generation uses a CSPRNG and samples without replacement.
class ChinesePassphraseCodec {
  ChinesePassphraseCodec._(this.words)
    : _pinyinToWord = {for (final word in words) word.pinyin: word},
      _hanziToWord = {for (final word in words) word.hanzi: word},
      _hanziLengths = words.map((word) => word.hanzi.length).toSet().toList()
        ..sort();

  factory ChinesePassphraseCodec.parse(String source) {
    final candidates = <PassphraseWord>[];
    for (final rawLine in source.split(RegExp(r'\r?\n'))) {
      final line = rawLine.replaceFirst('\ufeff', '').trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final fields = line.split(RegExp(r'\s+'));
      if (fields.length < 2) continue;
      candidates.add(PassphraseWord(fields.first.toLowerCase(), fields[1]));
    }

    final pinyinCounts = <String, int>{};
    final hanziCounts = <String, int>{};
    for (final word in candidates) {
      pinyinCounts.update(word.pinyin, (value) => value + 1, ifAbsent: () => 1);
      hanziCounts.update(word.hanzi, (value) => value + 1, ifAbsent: () => 1);
    }
    final safeWords = candidates
        .where(
          (word) =>
              pinyinCounts[word.pinyin] == 1 && hanziCounts[word.hanzi] == 1,
        )
        .toList(growable: false);
    if (safeWords.length < 1000) {
      throw const FormatException('安全词表条目不足');
    }
    return ChinesePassphraseCodec._(safeWords);
  }

  final List<PassphraseWord> words;
  final Map<String, PassphraseWord> _pinyinToWord;
  final Map<String, PassphraseWord> _hanziToWord;
  final List<int> _hanziLengths;

  ChinesePassphrase generate({int count = 6, Random? random}) {
    if (count < 4 || count > 12 || count > words.length) {
      throw RangeError.range(count, 4, min(12, words.length), 'count');
    }
    final secureRandom = random ?? Random.secure();
    final available = List<PassphraseWord>.of(words);
    final selected = <PassphraseWord>[];
    var entropyBits = 0.0;
    for (var index = 0; index < count; index++) {
      entropyBits += log(available.length) / ln2;
      final selectedIndex = secureRandom.nextInt(available.length);
      selected.add(available.removeAt(selectedIndex));
    }
    return ChinesePassphrase(List.unmodifiable(selected), entropyBits);
  }

  /// Converts either exact Chinese words or their pinyin keys into the stable
  /// pinyin form used by the KDF. Arbitrary homophones are intentionally not
  /// accepted.
  String canonicalize(String input, {required int wordCount}) {
    final normalized = input
        .trim()
        .replaceAll(RegExp(r'[·・,，、\-_]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) throw const FormatException('口令不能为空');

    final separated = normalized.split(' ');
    if (separated.length == wordCount) {
      final result = <String>[];
      for (final token in separated) {
        final lower = token.toLowerCase();
        final word = _pinyinToWord[lower] ?? _hanziToWord[token];
        if (word == null) throw const FormatException('口令不属于当前中文词表');
        result.add(word.pinyin);
      }
      return result.join(' ');
    }

    // Allow the generated Chinese display to be typed without separators. A
    // result is accepted only when it has one unambiguous segmentation.
    if (separated.length == 1 && RegExp(r'[^a-zA-Z]').hasMatch(normalized)) {
      final matches = <List<PassphraseWord>>[];
      void walk(int offset, List<PassphraseWord> path) {
        if (matches.length > 1 || path.length > wordCount) return;
        if (offset == normalized.length) {
          if (path.length == wordCount) matches.add(List.of(path));
          return;
        }
        for (final length in _hanziLengths) {
          final end = offset + length;
          if (end > normalized.length) break;
          final word = _hanziToWord[normalized.substring(offset, end)];
          if (word == null) continue;
          path.add(word);
          walk(end, path);
          path.removeLast();
        }
      }

      walk(0, <PassphraseWord>[]);
      if (matches.length == 1) {
        return matches.single.map((word) => word.pinyin).join(' ');
      }
    }
    throw const FormatException('中文词组口令的词数或分隔方式不正确');
  }
}
