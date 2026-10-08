import 'package:flutter_test/flutter_test.dart';

import '../support/speech_headless_checks.dart';

void main() {
  for (final entry in speechChecks().entries) {
    test(entry.key, entry.value);
  }
}
