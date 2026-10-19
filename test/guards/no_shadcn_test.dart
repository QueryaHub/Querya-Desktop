import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Epic #1465: `package:shadcn_flutter` is gone (#1736). Nothing may bring it
/// back: not an import, not the pubspec entry, not the vendored copy.
void main() {
  final importsShadcn = RegExp(
      r'''^(import|export)\s+['"]package:shadcn_flutter/''',
      multiLine: true);

  Map<String, String> sources() => {
        for (final e in Directory('lib').listSync(recursive: true))
          if (e is File && e.path.endsWith('.dart'))
            e.path.replaceAll(r'\', '/'): e.readAsStringSync(),
      };

  test('no file imports shadcn_flutter', () {
    final importing = <String>[
      for (final dir in ['lib', 'test', 'benchmark'])
        for (final e in Directory(dir).listSync(recursive: true))
          if (e is File &&
              e.path.endsWith('.dart') &&
              importsShadcn.hasMatch(e.readAsStringSync()))
            e.path.replaceAll(r'\', '/'),
    ];
    expect(importing, isEmpty, reason: 'shadcn_flutter was removed (#1736).');
  });

  test('pubspec and third_party no longer carry shadcn_flutter', () {
    expect(File('pubspec.yaml').readAsStringSync(),
        isNot(contains('shadcn_flutter')));
    expect(Directory('third_party/shadcn_flutter').existsSync(), isFalse);
  });

  test('text inputs are QueryaTextField, not a bare TextField (#1733)', () {
    final shadcnField = RegExp(r'(?<![\w.])TextField\(|\bInputFeature\.');
    final offenders = <String>[
      for (final MapEntry(:key, :value) in sources().entries)
        if (key != 'lib/shared/widgets/querya_text_field.dart' &&
            shadcnField.hasMatch(value))
          key,
    ];
    expect(offenders, isEmpty,
        reason: 'Use QueryaTextField.');
  });

  test('no hand-built material TextField outside the kit (#1733)', () {
    const kit = {
      'lib/shared/widgets/querya_text_field.dart',
      'lib/shared/widgets/querya_search_field.dart',
    };
    final offenders = <String>[
      for (final MapEntry(:key, :value) in sources().entries)
        if (!kit.contains(key) && value.contains('material.TextField('))
          key,
    ];
    expect(offenders, isEmpty,
        reason: 'Use QueryaTextField (framed: false inside a frame of your own).');
  });
}
