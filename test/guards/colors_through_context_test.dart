import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Epic #1465, #1731: colours are read through `context.colors`
/// (`QueryaUiColors`), not through a theme's `colorScheme`. `Theme.of` itself
/// stays allowed for what is not a colour (brightness, radius) until #1735.
///
/// The guard covers all of `lib/` except `lib/core/theme/`, which bridges to
/// the shadcn shell and leaves with #1465 step 5.
void main() {
  final banned = RegExp(r'\bcolorScheme\b|\bColorScheme\b');

  test('lib/ reads colours through context.colors (outside core/theme)', () {
    final offenders = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is! File || !e.path.endsWith('.dart')) continue;
      final normalized = e.path.replaceAll(r'\', '/');
      if (normalized.startsWith('lib/core/theme/')) continue;

      final lines = e.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (banned.hasMatch(line)) {
          offenders.add('$normalized:${i + 1}: ${line.trim()}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'Use context.colors (QueryaUiColors) instead.');
  });
}
