import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart'
    show formatVsCodeColor, parseQueryaThemeColor, parseVsCodeColor;

void main() {
  group('parseVsCodeColor', () {
    test('6-digit hex', () {
      expect(parseVsCodeColor('#1e1e1e'), const Color(0xFF1E1E1E));
    });

    test('8-digit RRGGBBAA', () {
      final c = parseVsCodeColor('#11223344');
      expect((c.a * 255).round(), 0x44);
    });

    test('3-digit shorthand', () {
      expect(parseVsCodeColor('#abc'), const Color(0xFFAABBCC));
    });

    test('4-digit shorthand with alpha', () {
      final c = parseVsCodeColor('#abcd');
      expect(c, isA<Color>());
    });

    test('invalid throws', () {
      expect(() => parseVsCodeColor('nope'), throwsFormatException);
    });

    test('formatVsCodeColor roundtrip', () {
      const c = Color(0xFF1E1E1E);
      expect(formatVsCodeColor(c), '#1e1e1e');
      expect(parseVsCodeColor(formatVsCodeColor(c)), c);
    });
  });

  group('parseQueryaThemeColor', () {
    test('parses hash-prefixed RRGGBB', () {
      expect(parseQueryaThemeColor('#1E1E1E'), const Color(0xFF1E1E1E));
    });

    test('parses bare RRGGBB', () {
      expect(parseQueryaThemeColor('1E1E1E'), const Color(0xFF1E1E1E));
    });

    test('parses hash-prefixed AARRGGBB', () {
      expect(parseQueryaThemeColor('#801E1E1E'), const Color(0x801E1E1E));
    });

    test('parses bare AARRGGBB', () {
      expect(parseQueryaThemeColor('FF1E1E1E'), const Color(0xFF1E1E1E));
    });

    test('accepts lowercase hex', () {
      expect(parseQueryaThemeColor('#ff1e1e1e'), const Color(0xFF1E1E1E));
      expect(parseQueryaThemeColor('1e1e1e'), const Color(0xFF1E1E1E));
    });

    test('delegates shorthand RGB to parseVsCodeColor', () {
      expect(parseQueryaThemeColor('#abc'), const Color(0xFFAABBCC));
    });

    test('invalid length mentions value', () {
      expect(
        () => parseQueryaThemeColor('12345'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid Querya theme color: 12345',
          ),
        ),
      );
    });

    test('invalid characters mention value', () {
      expect(
        () => parseQueryaThemeColor('GGHHII'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid Querya theme color: GGHHII',
          ),
        ),
      );
    });

    test('empty string mentions value', () {
      expect(
        () => parseQueryaThemeColor('   '),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            'Invalid Querya theme color:    ',
          ),
        ),
      );
    });
  });
}
