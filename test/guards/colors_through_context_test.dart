import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Epic #1465, #1731: colours are read through `context.colors`
/// (`QueryaUiColors`), not through a theme's `colorScheme`. A folder joins
/// [migrated] in the PR that moves it; at the end the list is all of `lib/`.
void main() {
  const migrated = <String>[
    'lib/features/connections',
  ];

  final banned = RegExp(r'\bcolorScheme\b|\bTheme\.of\(|\bColorScheme\b');

  test('migrated folders read colours through context.colors', () {
    final offenders = <String>[];
    for (final dir in migrated) {
      for (final e in Directory(dir).listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final lines = e.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (banned.hasMatch(line)) {
            offenders.add('${e.path.replaceAll(r'\', '/')}:${i + 1}: '
                '${line.trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.colors (QueryaUiColors) instead.');
  });
}
