import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';

void main() {
  const rules = [
    TokenColorRule(scopes: ['keyword'], foreground: '#ff0000'),
    TokenColorRule(scopes: ['string', 'string.quoted'], foreground: '#00ff00'),
  ];

  group('QueryaTheme.tokenColorsHash (#1353)', () {
    test('equals the hash of the token colours', () {
      final theme = QueryaTheme.darkDefault.copyWith(tokenColors: rules);

      expect(theme.tokenColorsHash, Object.hashAll(rules));
    });

    test('is stable across reads', () {
      final theme = QueryaTheme.darkDefault.copyWith(tokenColors: rules);

      expect(theme.tokenColorsHash, theme.tokenColorsHash);
    });

    test('themes sharing a list share the hash', () {
      final a = QueryaTheme.darkDefault.copyWith(tokenColors: rules);
      final b = a.copyWith(brightness: a.brightness);
      final mid = QueryaTheme.lerp(a, b, 0.25);

      expect(b.tokenColorsHash, a.tokenColorsHash);
      expect(mid.tokenColorsHash, a.tokenColorsHash);
    });

    test('different rules give a different hash', () {
      final a = QueryaTheme.darkDefault.copyWith(tokenColors: rules);
      final b = QueryaTheme.darkDefault.copyWith(
        tokenColors: const [
          TokenColorRule(scopes: ['comment'], foreground: '#888888'),
        ],
      );

      expect(a.tokenColorsHash, isNot(b.tokenColorsHash));
    });

    test('a theme without token colours has the empty-list hash', () {
      expect(
        QueryaTheme.darkDefault.tokenColorsHash,
        Object.hashAll(const <TokenColorRule>[]),
      );
    });
  });
}
