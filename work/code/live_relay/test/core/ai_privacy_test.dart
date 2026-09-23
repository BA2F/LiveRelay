import 'package:flutter_test/flutter_test.dart';
import 'package:live_relay/core/ai/ai_privacy.dart';
import 'package:live_relay/core/domain/entities.dart';

void main() {
  const processor = AiPrivacyProcessor();
  const lines = [
    OcrLine(
      text: '户名 alice@example.com',
      left: 0,
      top: 0,
      right: 100,
      bottom: 20,
      order: 0,
    ),
    OcrLine(
      text: '密码 exact-secret',
      left: 0,
      top: 21,
      right: 100,
      bottom: 40,
      order: 1,
    ),
    OcrLine(
      text: '房产证放在书房',
      left: 0,
      top: 41,
      right: 100,
      bottom: 60,
      order: 2,
    ),
  ];
  const marks = [
    SensitiveMark(lineOrder: 0, kind: SensitiveFieldKind.account),
    SensitiveMark(lineOrder: 1, kind: SensitiveFieldKind.secret),
  ];

  test('tokenizes marked lines without exposing their values', () {
    final payload = processor.tokenize(lines: lines, marks: marks);

    expect(payload.redactedText, contains('[[ACCOUNT_01]]'));
    expect(payload.redactedText, contains('[[SECRET_01]]'));
    expect(payload.redactedText, contains('房产证放在书房'));
    expect(payload.redactedText, isNot(contains('exact-secret')));
    expect(payload.tokenMap['[[SECRET_01]]'], '密码 exact-secret');
  });

  test('validates tokens and rehydrates only valid structured drafts', () {
    final payload = processor.tokenize(lines: lines, marks: marks);
    final result = processor.validateAndRehydrate(
      '''{"cards":[{"title":"账户 [[ACCOUNT_01]]","content":"[[SECRET_01]] · 房产证放在书房","kind":"account","inference":false}]}''',
      payload,
    );

    expect(result, hasLength(1));
    expect(result.single.title, contains('alice@example.com'));
    expect(result.single.content, contains('exact-secret'));
    expect(result.single.toDraft().status, CardStatus.draft);
  });

  test('rejects missing, duplicate, and invented tokens', () {
    final payload = processor.tokenize(lines: lines, marks: marks);

    for (final response in [
      '''{"cards":[{"title":"[[ACCOUNT_01]]","content":"丢了密码","kind":"account","inference":false}]}''',
      '''{"cards":[{"title":"[[ACCOUNT_01]]","content":"[[SECRET_01]] [[SECRET_01]]","kind":"account","inference":false}]}''',
      '''{"cards":[{"title":"[[ACCOUNT_01]]","content":"[[SECRET_01]] [[MONEY_01]]","kind":"account","inference":false}]}''',
      '''{"cards":[{"title":"[[ACCOUNT_01]]","content":"[[SECRET_01]] [[ALIEN_01]]","kind":"account","inference":false}]}''',
    ]) {
      expect(
        () => processor.validateAndRehydrate(response, payload),
        throwsA(isA<FormatException>()),
      );
    }
  });
}
