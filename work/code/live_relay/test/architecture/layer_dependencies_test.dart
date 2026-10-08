import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Import graph guard, including transitive compatibility exports. Internal
// aliases remain only for old callers; actual use cases cannot reach them.
final directives = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);
String? localTarget(String source, String uri) {
  if (uri.startsWith('package:live_relay/')) return 'lib/${uri.substring(19)}';
  if (uri.startsWith('dart:') || uri.startsWith('package:')) return null;
  final parts = <String>[];
  for (final part in '${File(source).parent.path}/$uri'.split('/')) {
    if (part == '.') continue;
    if (part == '..') {
      parts.removeLast();
    } else {
      parts.add(part);
    }
  }
  return parts.join('/');
}

void main() {
  test(
    'domain and application implementation dependency graph stays inward',
    () {
      final sources = {
        for (final f
            in Directory('lib')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
          f.path: f.readAsStringSync(),
      };
      bool compatibilityOnly(String source) {
        final text = sources[source]!
            .replaceAll(RegExp(r'//[^\n]*'), '')
            .trim();
        return text.isNotEmpty &&
            text
                .split(';')
                .where((s) => s.trim().isNotEmpty)
                .every((s) => s.trim().startsWith('export '));
      }

      final violations = <String>{};
      void inspect(String file, String origin, Set<String> visited) {
        if (!visited.add(file)) return;
        for (final m in directives.allMatches(sources[file]!)) {
          final uri = m[1]!;
          if (uri == 'dart:ui' ||
              uri.startsWith('package:flutter') ||
              uri.startsWith('package:drift') ||
              uri.startsWith('package:sqflite') ||
              uri.startsWith('package:path_provider') ||
              uri.startsWith('package:window_manager')) {
            violations.add('$origin -> $file -> $uri');
          }
          final target = localTarget(file, uri);
          if (target == null || !sources.containsKey(target)) continue;
          if (target.startsWith('lib/presentation/') ||
              target.startsWith('lib/infrastructure/')) {
            violations.add('$origin -> $file -> $target');
          } else {
            inspect(target, origin, visited);
          }
        }
      }

      for (final file in sources.keys) {
        if (file.startsWith('lib/core/')) {
          for (final m in directives.allMatches(sources[file]!)) {
            final target = localTarget(file, m[1]!);
            if (target != null && !target.startsWith('lib/core/')) {
              violations.add('$file -> $target');
            }
          }
          inspect(file, file, {});
        } else if (file.startsWith('lib/application/') &&
            !compatibilityOnly(file)) {
          inspect(file, file, {});
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    },
  );
}
