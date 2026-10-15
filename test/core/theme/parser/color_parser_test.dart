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

  group('hex scanner (#1541)', () {
    test('4-digit shorthand is RGBA, each nibble doubled', () {
      expect(parseVsCodeColor('#1234'), const Color(0x44112233));
      expect(parseVsCodeColor('f08c'), const Color(0xCCFF0088));
    });

    test('8-digit VS Code value is RRGGBBAA, Querya value is AARRGGBB', () {
      expect(parseVsCodeColor('#11223344'), const Color(0x44112233));
      expect(parseQueryaThemeColor('#44112233'), const Color(0x44112233));
    });

    test('upper and lower case digits parse the same', () {
      expect(parseVsCodeColor('#AbCdEf'), parseVsCodeColor('#abcdef'));
      expect(parseVsCodeColor('#AbCdEf'), const Color(0xFFABCDEF));
    });

    test('signs, spaces and non-hex characters are rejected', () {
      for (final bad in ['#+12345', '#-12345', '#12 456', '#12345g', '#zzz']) {
        expect(() => parseVsCodeColor(bad), throwsFormatException,
            reason: bad);
      }
      expect(() => parseQueryaThemeColor('+1234567'), throwsFormatException);
    });

    test('formatVsCodeColor writes lowercase hex and alpha only when needed',
        () {
      expect(formatVsCodeColor(const Color(0xFF000000)), '#000000');
      expect(formatVsCodeColor(const Color(0xFF0A0B0C)), '#0a0b0c');
      expect(formatVsCodeColor(const Color(0x80112233)), '#11223380');
    });

    test('every channel value round-trips through format and parse', () {
      for (var v = 0; v < 256; v++) {
        final c = Color.fromARGB(0xFF, v, 255 - v, v ^ 0x5A);
        expect(parseVsCodeColor(formatVsCodeColor(c)), c, reason: 'v=$v');
      }
    });
  });
}
