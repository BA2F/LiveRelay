import 'package:flutter_test/flutter_test.dart';

import '../support/agent_service_headless_checks.dart';

void main() {
  for (final entry in agentServiceChecks().entries) {
    test(entry.key, entry.value);
  }
}
