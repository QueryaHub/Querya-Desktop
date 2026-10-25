import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Error-handling epic (#1764, #1763): a `catch` in the UI layer must do
/// something with the error: `logIgnored`, the reporting helpers, a rethrow or
/// a real fallback. An empty block (or one that holds only a comment) hides a
/// failure from both the user and the log.
///
/// The files below keep a few empty blocks on purpose: they try to parse a
/// value in a second form and fall back, so the failure is the control flow.
/// The number is exact, so removing one of them has to lower it here too.
void main() {
  const allowed = {
    'lib/features/mongodb/mongo_field_codec.dart': 1,
    'lib/features/mongodb/mql_parser.dart': 1,
    'lib/features/workspace/data_grid_value_panel.dart': 6,
  };

  final emptyCatch = RegExp(
    r'catch\s*\([^)]*\)\s*\{(?:\s|//[^\n]*|/\*[\s\S]*?\*/)*\}',
  );

  String norm(File f) => f.path.replaceAll(r'\', '/');

  test('lib/features and lib/shared have no empty catch blocks', () {
    final counts = <String, int>{};
    for (final dir in ['lib/features', 'lib/shared']) {
      for (final e in Directory(dir).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final n = emptyCatch.allMatches(e.readAsStringSync()).length;
        if (n > 0) counts[norm(e)] = n;
      }
    }

    final problems = <String>[];
    for (final entry in counts.entries) {
      final expected = allowed[entry.key] ?? 0;
      if (entry.value > expected) {
        problems.add('${entry.key}: ${entry.value} empty catch blocks '
            '(allowed $expected): call logIgnored(where, e, st) or report it');
      }
    }
    for (final entry in allowed.entries) {
      final actual = counts[entry.key] ?? 0;
      if (actual < entry.value) {
        problems.add('${entry.key}: ${entry.value} allowed but only $actual '
            'left: lower the number in this test');
      }
    }

    expect(problems, isEmpty, reason: problems.join('\n'));
  });
}
