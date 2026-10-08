import 'package:flutter_test/flutter_test.dart';

import '../support/device_identity_headless_checks.dart';

void main() {
  for (final entry in deviceIdentityChecks().entries) {
    test(entry.key, entry.value);
  }
}
