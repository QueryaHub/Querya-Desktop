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

    test('keeps string literals byte for byte, escapes included', () {
      const input = r'{"a": "q\"uote // not a comment", "b": "back\\"}';
      expect(stripJsonc(input), input);
    });

    test('comment markers and trailing commas inside strings survive', () {
      const input = r'{"a": "/* x */", "b": "[1,]", "c": "x,}"}';
      expect(stripJsonc(input), input);
    });

    test('an unterminated string is copied to the end', () {
      expect(stripJsonc('{"a": "oops'), '{"a": "oops');
    });

    test('a trailing backslash at the end of input does not throw', () {
      expect(stripJsonc(r'{"a": "x\'), r'{"a": "x\');
    });

    test('comments and trailing commas around many strings', () {
      final input = StringBuffer('{\n');
      for (var i = 0; i < 200; i++) {
        input.write('  // token $i\n  "k$i": "#${i.toRadixString(16).padLeft(6, '0')}",\n');
      }
      input.write('}');
      final cleaned = stripJsonc(input.toString());
      expect(cleaned.contains('//'), isFalse);
      expect(cleaned.contains(',\n}'), isFalse);
      expect(cleaned, contains('"k199": "#0000c7"'));
    });
  });
}
