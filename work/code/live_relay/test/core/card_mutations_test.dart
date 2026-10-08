import 'package:flutter_test/flutter_test.dart';

import '../support/card_rules_headless_checks.dart';

void main() {
  for (final entry in cardRuleChecks().entries) {
    test(entry.key, entry.value);
  }
}
