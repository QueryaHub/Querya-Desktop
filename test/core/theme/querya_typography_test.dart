import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_editor_theme.dart';
import 'package:querya_desktop/core/theme/querya_typography.dart';

void main() {
  group('QueryaTypography font stack', () {
    test('defines modern primary monospace and cross-platform fallback stack', () {
      expect(QueryaTypography.mono, equals('Cascadia Code'));

      const stack = QueryaTypography.monoFontFamilyFallback;
      expect(stack, contains('Cascadia Code'));
      expect(stack, contains('Consolas'));
      expect(stack, contains('Menlo'));
      expect(stack, contains('SF Mono'));
      expect(stack, contains('Fira Code'));
      expect(stack, contains('Ubuntu Mono'));
      expect(stack, contains('DejaVu Sans Mono'));
      expect(stack, contains('monospace'));

      // The generic 'monospace' closes the Latin stack; the CJK tail follows it
      // (#1553), so Latin text keeps rendering in the monospace fonts.
      const cjk = QueryaTypography.cjkFontFamilyFallback;
      expect(stack.sublist(stack.length - cjk.length), equals(cjk));
      expect(stack[stack.length - cjk.length - 1], equals('monospace'));
    });

    test('CJK fallback names a family for each desktop platform (#1553)', () {
      const cjk = QueryaTypography.cjkFontFamilyFallback;
      expect(cjk, contains('Noto Sans CJK SC'));
      expect(cjk, contains('PingFang SC'));
      expect(cjk, contains('Microsoft YaHei'));
      expect(cjk, isNot(contains('monospace')));
      expect(cjk.toSet().length, cjk.length); // no duplicates
    });

    test('QueryaEditorTheme wires monospace typography stack by default', () {
      const theme = QueryaEditorTheme.darkDefault;
      expect(theme.fontFamily, equals(QueryaTypography.mono));
      expect(theme.fontFamilyFallback, equals(QueryaTypography.monoFontFamilyFallback));
    });

    test('QueryaEditorTheme copyWith and lerp preserve or override fontFamilyFallback', () {
      const base = QueryaEditorTheme.darkDefault;
      final custom = base.copyWith(
        fontFamily: 'Fira Code',
        fontFamilyFallback: ['Fira Code', 'monospace'],
      );
      expect(custom.fontFamily, equals('Fira Code'));
      expect(custom.fontFamilyFallback, equals(['Fira Code', 'monospace']));

      final lerped = QueryaEditorTheme.lerp(base, custom, 0.7);
      expect(lerped.fontFamily, equals('Fira Code'));
      expect(lerped.fontFamilyFallback, equals(['Fira Code', 'monospace']));
    });
  });
}
