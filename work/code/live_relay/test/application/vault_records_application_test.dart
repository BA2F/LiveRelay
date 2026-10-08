import 'package:flutter_test/flutter_test.dart';

import '../support/records_headless_checks.dart';

void main() {
  for (final entry in {...recordsChecks(), ...ownerAgentChecks()}.entries) {
    test(entry.key, entry.value);
  }
}
