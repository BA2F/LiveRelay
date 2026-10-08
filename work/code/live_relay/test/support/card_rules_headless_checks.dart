// Pure domain verification, executable independently of Flutter and SQLite.
import 'dart:io';

import 'package:live_relay/core/domain/entities.dart';
import 'package:live_relay/core/domain/card_mutations.dart';
import 'package:live_relay/core/domain/card_references.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

void reject(void Function() operation, String message) {
  Object? failure;
  try {
    operation();
  } on Object catch (e) {
    failure = e;
  }
  check(
    failure != null && '$failure'.contains(message),
    'Expected $message; got $failure',
  );
}

LifeCard card(String id, {bool deleted = false}) => LifeCard(
  id: id,
  title: 'Public title',
  content: 'Public body',
  kind: CardKind.note,
  status: CardStatus.draft,
  tags: const ['public'],
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  revisionNumber: 4,
  deletedAt: deleted ? DateTime.utc(2026) : null,
);
Map<String, void Function()> cardRuleChecks() => {
  'domain split preserves parent and rejects invalid later child before persistence':
      () {
        final parts = [
          const CardDraft(title: 'Public child', content: 'Public body'),
          const CardDraft(title: '', content: 'Invalid'),
        ];
        reject(() => SplitCardPlan(card('a'), parts), '标题不能为空');
        parts[1] = const CardDraft(
          title: 'Second child',
          content: 'Public body',
        );
        final plan = SplitCardPlan(card('a'), parts);
        parts.clear();
        check(
          plan.parts.length == 2 &&
              plan.parent.status == CardStatus.split &&
              plan.parent.title == 'Public title' &&
              plan.revision == 5 &&
              plan.parentId == 'a',
          'Mutable or lossy split plan',
        );
        reject(
          () => SplitCardPlan(card('a', deleted: true), plan.parts),
          '卡片不存在',
        );
      },
  'domain bundle preserves selected order and rejects recycled members': () {
    final ids = ['b', 'a'], plan = BundleCardPlan('Public bundle', ids);
    ids.clear();
    plan.validateMembers({'a': card('a'), 'b': card('b')});
    check(
      plan.memberIds.join(',') == 'b,a' && plan.draft.kind == CardKind.bundle,
      'Bundle lost membership',
    );
    reject(
      () =>
          plan.validateMembers({'a': card('a'), 'b': card('b', deleted: true)}),
      '组合成员不存在',
    );
    reject(() => BundleCardPlan('Public bundle', ['a', 'a']), '重复');
  },
  'domain reference replacement preserves other cards and bounds self disclosure':
      () {
        final targets = CardReferenceRules.targets('a', ['b', 'b']);
        CardReferenceRules.validate('a', targets, {
          'a': card('a'),
          'b': card('b'),
        });
        final next = CardReferenceRules.replace(
          [const CardReference('x', 'y'), const CardReference('a', 'z')],
          'a',
          targets,
        );
        check(
          next.length == 2 && next.first.from == 'x' && next.last.to == 'b',
          'References lost another owner or duplicated',
        );
        reject(
          () => CardReferenceRules.validate('a', targets, {
            'a': card('a'),
            'b': card('b', deleted: true),
          }),
          '引用目标不存在',
        );
        reject(() => CardReferenceRules.targets('a', ['a']), '不能引用自身');
        reject(
          () => CardReferenceRules.targets(
            'a',
            List.generate(201, (i) => 'target$i'),
          ),
          '最多 200',
        );
      },
  'domain draft validation preserves credential spaces and ordered normalized tags':
      () {
        DraftRules.validateCredential(
          const CredentialDraft(title: 'Public credential', username: 'public', secret: '  '),
        );
        reject(
          () => DraftRules.validateCredential(
            const CredentialDraft(title: 'Public credential', username: 'public', secret: ''),
          ),
          '密码不能为空',
        );
        reject(
          () => DraftRules.validateCard(
            const CardDraft(title: 'Public card', content: ' \n '),
          ),
          '内容不能为空',
        );
        check(
          DraftRules.normalizedTags([' b ', 'a', 'b', ' ']).join(',') == 'b,a',
          'Tag normalization changed order',
        );
      },
};
void main() {
  for (final entry in cardRuleChecks().entries) {
    entry.value();
    stdout.writeln('PASS ${entry.key}');
  }
}
