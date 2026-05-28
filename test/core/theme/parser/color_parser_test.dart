import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/color_parser.dart'
    show formatVsCodeColor, parseVsCodeColor;

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
}
