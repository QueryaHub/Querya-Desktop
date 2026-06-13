import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';

void main() {
  group('ThemeDefinition', () {
    test('isFileBacked is true for file-backed sources', () {
      expect(
        _definition(source: ThemeSource.filesystem).isFileBacked,
        isTrue,
      );
      expect(
        _definition(source: ThemeSource.imported).isFileBacked,
        isTrue,
      );
      expect(
        _definition(source: ThemeSource.legacyImported).isFileBacked,
        isTrue,
      );
    });

    test('isFileBacked is false for built-in themes', () {
      expect(
        _definition(source: ThemeSource.builtin).isFileBacked,
        isFalse,
      );
    });

    test('stableCacheKey includes source, id, and content hash', () {
      final definition = _definition(
        id: 'cyberpunk-neon',
        source: ThemeSource.filesystem,
        contentHash: 'hash-v1',
      );

      expect(
        definition.stableCacheKey,
        'filesystem:cyberpunk-neon:hash-v1',
      );
    });

    test('stableCacheKey changes when contentHash changes', () {
      final base = _definition(contentHash: 'hash-v1');
      final updated = _definition(contentHash: 'hash-v2');

      expect(base.stableCacheKey, isNot(updated.stableCacheKey));
    });

    test('stableCacheKey falls back to path then name without hash', () {
      final withPath = _definition(
        contentHash: null,
        path: '/data/themes/custom.json',
      );
      final withNameOnly = _definition(
        contentHash: null,
        path: null,
        name: 'Querya Dark',
      );

      expect(withPath.stableCacheKey, contains('/data/themes/custom.json'));
      expect(withNameOnly.stableCacheKey, endsWith('Querya Dark'));
    });

    test('value equality compares metadata fields', () {
      final a = _definition(contentHash: 'hash-v1');
      final b = _definition(contentHash: 'hash-v1');
      final c = _definition(contentHash: 'hash-v2');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}

ThemeDefinition _definition({
  String id = 'fixture-custom-dark',
  String name = 'Fixture Custom Dark',
  ThemeSource source = ThemeSource.filesystem,
  ThemeFormat format = ThemeFormat.queryaCustom,
  bool isDark = true,
  String? path = '/tmp/fixture-custom-dark.json',
  DateTime? lastModified,
  String? contentHash = 'abc123',
}) {
  return ThemeDefinition(
    id: id,
    name: name,
    source: source,
    format: format,
    isDark: isDark,
    path: path,
    lastModified: lastModified,
    contentHash: contentHash,
  );
}
