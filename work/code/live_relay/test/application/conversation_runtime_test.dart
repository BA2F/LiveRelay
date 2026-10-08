import 'package:flutter_test/flutter_test.dart';

import '../support/conversation_headless_checks.dart';

void main() {
  for (final entry in conversationChecks().entries) {
    test(entry.key, entry.value);
  }
}
