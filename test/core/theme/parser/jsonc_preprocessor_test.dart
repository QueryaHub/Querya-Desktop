import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/jsonc_preprocessor.dart';

void main() {
  group('stripJsonc', () {
    test('removes line comments outside strings', () {
      const input = '''
{
  // sidebar
  "a": 1
}
''';
      final out = stripJsonc(input);
      expect(out.contains('//'), isFalse);
      expect(out.contains('"a"'), isTrue);
    });

    test('preserves // inside string', () {
      const input = '{"x": "http://example.com"}';
      expect(stripJsonc(input), contains('http://'));
    });

    test('removes block comments', () {
      const input = '{ /* block */ "k": 2 }';
      final out = stripJsonc(input);
      expect(out.contains('/*'), isFalse);
      expect(out.contains('"k"'), isTrue);
    });

    test('removes trailing comma', () {
      const input = '{"a": 1,}';
      expect(stripJsonc(input), '{"a": 1}');
    });

    test('parses invalid-trailing-comma.jsonc fixture via manifest', () {
      final raw = File('test/fixtures/themes/invalid-trailing-comma.jsonc')
          .readAsStringSync();
      final cleaned = stripJsonc(raw);
      expect(cleaned.contains('//'), isFalse);
      expect(cleaned.contains(',}'), isFalse);
      expect(cleaned, contains('"editor.background"'));
    });
  });
}
