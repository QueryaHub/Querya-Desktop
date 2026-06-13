import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';

void main() {
  group('QueryaThemeManifest', () {
    test('parses full dark fixture', () {
      final raw =
          File('test/fixtures/themes/querya_custom_dark.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(manifest.schema, queryaThemeSchemaV1);
      expect(manifest.id, 'fixture-custom-dark');
      expect(manifest.name, 'Fixture Custom Dark');
      expect(manifest.type, QueryaThemeType.dark);
      expect(manifest.isDark, isTrue);
      expect(manifest.shadcnColors['primary'], '#38BDF8');
      expect(manifest.editorColors['background'], '#0F1117');
      expect(manifest.tokenColors.length, 3);
      expect(manifest.description, isNotNull);
      expect(manifest.author, 'QueryaHub');
      expect(manifest.version, '1.0.0');
    });

    test('parses full light fixture', () {
      final raw =
          File('test/fixtures/themes/querya_custom_light.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(manifest.type, QueryaThemeType.light);
      expect(manifest.isLight, isTrue);
      expect(manifest.shadcnColors['background'], '#F8FAFC');
      expect(manifest.editorColors['foreground'], '#1E293B');
      expect(manifest.tokenColors.length, 3);
      expect(
        manifest.tokenColors.last.scopes,
        ['string'],
      );
    });

    test('parses minimal fixture with sparse colors', () {
      final raw =
          File('test/fixtures/themes/querya_custom_minimal.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(manifest.id, 'fixture-custom-minimal');
      expect(manifest.shadcnColors, {'primary': '#FF00AA'});
      expect(manifest.editorColors, {'background': '#010203'});
      expect(manifest.tokenColors, isEmpty);
      expect(manifest.description, isNull);
    });

    test('parses JSONC fixture with comments and trailing commas', () {
      final raw =
          File('test/fixtures/themes/querya_custom_jsonc.jsonc').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(manifest.id, 'fixture-custom-jsonc');
      expect(manifest.type, QueryaThemeType.light);
      expect(manifest.shadcnColors['primary'], '#0EA5E9');
      expect(manifest.editorColors['foreground'], '#111827');
      expect(manifest.tokenColors.single.foreground, '#6B7280');
    });

    test('accepts empty shadcn_colors and editor_colors objects', () {
      const src = '''
{
  "schema": "querya.theme.v1",
  "id": "empty-maps",
  "name": "Empty Maps",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {}
}
''';
      final manifest = QueryaThemeManifest.fromJsonString(src);

      expect(manifest.shadcnColors, isEmpty);
      expect(manifest.editorColors, isEmpty);
    });

    test('returns unmodifiable color maps', () {
      final raw =
          File('test/fixtures/themes/querya_custom_minimal.json').readAsStringSync();
      final manifest = QueryaThemeManifest.fromJsonString(raw);

      expect(
        () => manifest.shadcnColors['new'] = '#000000',
        throwsA(isA<UnsupportedError>()),
      );
      expect(
        () => manifest.editorColors['new'] = '#000000',
        throwsA(isA<UnsupportedError>()),
      );
    });

    test('ignores unknown root fields', () {
      const src = '''
{
  "schema": "querya.theme.v1",
  "id": "with-unknown",
  "name": "Unknown Fields",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {},
  "futureField": true
}
''';
      final manifest = QueryaThemeManifest.fromJsonString(src);
      expect(manifest.id, 'with-unknown');
    });

    test('throws when id is missing', () {
      final raw = File('test/fixtures/themes/querya_custom_invalid_missing_id.json')
          .readAsStringSync();

      expect(
        () => QueryaThemeManifest.fromJsonString(raw),
        throwsA(
          isA<QueryaThemeManifestParseException>().having(
            (e) => e.message,
            'message',
            contains('id'),
          ),
        ),
      );
    });

    test('throws on invalid type', () {
      const src = '''
{
  "schema": "querya.theme.v1",
  "id": "bad-type",
  "name": "Bad Type",
  "type": "neon",
  "shadcn_colors": {},
  "editor_colors": {}
}
''';
      expect(
        () => QueryaThemeManifest.fromJsonString(src),
        throwsA(
          isA<QueryaThemeManifestParseException>().having(
            (e) => e.message,
            'message',
            contains('Invalid type'),
          ),
        ),
      );
    });

    test('throws on unsupported schema', () {
      const src = '''
{
  "schema": "querya.theme.v2",
  "id": "future",
  "name": "Future",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {}
}
''';
      expect(
        () => QueryaThemeManifest.fromJsonString(src),
        throwsA(isA<QueryaThemeManifestParseException>()),
      );
    });

    test('throws on invalid JSON', () {
      expect(
        () => QueryaThemeManifest.fromJsonString('{ not json }'),
        throwsA(isA<QueryaThemeManifestParseException>()),
      );
    });

    test('reuses TokenColorRule parsing from VS Code themes', () {
      const src = '''
{
  "schema": "querya.theme.v1",
  "id": "tokens",
  "name": "Tokens",
  "type": "dark",
  "shadcn_colors": {},
  "editor_colors": {},
  "tokenColors": [
    {
      "scope": ["keyword", "storage.type"],
      "settings": { "foreground": "#569CD6", "fontStyle": "italic" }
    }
  ]
}
''';
      final manifest = QueryaThemeManifest.fromJsonString(src);
      expect(manifest.tokenColors.single, isA<TokenColorRule>());
      expect(manifest.tokenColors.single.scopes, ['keyword', 'storage.type']);
    });
  });
}
