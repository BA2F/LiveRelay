import 'package:flutter_test/flutter_test.dart';

import '../support/workbench_headless_checks.dart';

void main() {
  for (final entry in workbenchChecks().entries) {
    test(entry.key, entry.value);
  }
}
