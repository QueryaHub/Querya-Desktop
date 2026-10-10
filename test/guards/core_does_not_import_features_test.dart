import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// #1239: the dependency direction is features → core/shared, never the
/// reverse (`docs/architecture.md`). `lib/app/` wires the two together.
void main() {
  test('lib/core and lib/shared import neither features/ nor app/', () {
    final banned = RegExp(
      r'''^\s*(import|export)\s+['"]('''
      r'''package:querya_desktop/(features|app)/'''
      r'''|(\.\./)+(features|app)/)''',
      multiLine: true,
    );
    final offenders = <String>[];
    for (final root in ['lib/core', 'lib/shared']) {
      for (final f in Directory(root).listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        for (final m in banned.allMatches(f.readAsStringSync())) {
          offenders.add('${f.path}: ${m.group(0)!.trim()}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
