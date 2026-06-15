import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/theme_metadata.dart';

void main() {
  group('ThemeMetadata', () {
    test('fromQueryaJson returns null when no metadata fields present', () {
      expect(
        ThemeMetadata.fromQueryaJson(const {
          'schema': 'querya.theme.v1',
          'id': 'bare',
          'name': 'Bare',
        }),
        isNull,
      );
    });

    test('fromQueryaJson parses marketplace fields', () {
      final metadata = ThemeMetadata.fromQueryaJson({
        'description': ' Neon preset ',
        'author': ' QueryaHub ',
        'version': '1.2.3',
        'homepage': 'https://querya.example/themes/neon',
        'license': 'MIT',
        'preview': 'https://cdn.example/preview.png',
        'tags': [' neon ', 'dark', '', 42, 'cyberpunk'],
      });

      expect(metadata, isNotNull);
      expect(metadata!.description, 'Neon preset');
      expect(metadata.author, 'QueryaHub');
      expect(metadata.version, '1.2.3');
      expect(metadata.homepage, 'https://querya.example/themes/neon');
      expect(metadata.license, 'MIT');
      expect(metadata.preview, 'https://cdn.example/preview.png');
      expect(metadata.tags, ['neon', 'dark', 'cyberpunk']);
    });

    test('pickerSubtitle prefers author over tags', () {
      const metadata = ThemeMetadata(
        author: 'QueryaHub',
        tags: ['dark', 'neon'],
      );

      expect(metadata.pickerSubtitle, 'QueryaHub');
    });

    test('pickerSubtitle falls back to tags', () {
      const metadata = ThemeMetadata(tags: ['dark', 'neon']);

      expect(metadata.pickerSubtitle, 'dark, neon');
    });
  });
}
