import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_load_result.dart';

void main() {
  const definition = ThemeDefinition(
    id: 'fixture-custom-dark',
    name: 'Fixture Custom Dark',
    source: ThemeSource.filesystem,
    format: ThemeFormat.queryaCustom,
    isDark: true,
    path: '/tmp/fixture-custom-dark.json',
    contentHash: 'abc123',
  );

  group('ThemeLoadResult', () {
    test('success carries definition and theme', () {
      const result = ThemeLoadSuccess(
        definition: definition,
        theme: QueryaTheme.darkDefault,
      );

      expect(result, isA<ThemeLoadSuccess>());
      expect(result.definition.id, 'fixture-custom-dark');
      expect(result.theme.brightness, QueryaTheme.darkDefault.brightness);
    });

    test('failure carries definition, message, and optional error', () {
      final error = StateError('parse failed');
      final result = ThemeLoadFailure(
        definition: definition,
        message: 'Invalid theme file.',
        error: error,
      );

      expect(result, isA<ThemeLoadFailure>());
      expect(result.definition.path, definition.path);
      expect(result.message, 'Invalid theme file.');
      expect(result.error, same(error));
    });

    test('sealed result supports pattern matching', () {
      const ThemeLoadResult result = ThemeLoadSuccess(
        definition: definition,
        theme: QueryaTheme.lightDefault,
      );

      final matched = switch (result) {
        ThemeLoadSuccess(:final theme) => theme.brightness,
        ThemeLoadFailure() => null,
      };

      expect(matched, QueryaTheme.lightDefault.brightness);
    });
  });
}
