import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/extension_paths.dart';
import 'package:querya_desktop/core/market/extension_manifest.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_metadata.dart';

void main() {
  group('ExtensionManifest', () {
    test('fromThemeDefinition maps registry metadata field names', () {
      const definition = ThemeDefinition(
        id: 'cyberpunk-neon',
        name: 'Cyberpunk Neon',
        source: ThemeSource.filesystem,
        format: ThemeFormat.queryaCustom,
        isDark: true,
        contentHash: 'abc12345',
        metadata: ThemeMetadata(
          author: 'QueryaHub',
          description: 'Neon theme',
          version: '1.0.0',
          homepage: 'https://example.com',
          license: 'MIT',
          preview: 'https://cdn.example/preview.png',
          tags: ['neon'],
        ),
      );

      final manifest = ExtensionManifest.fromThemeDefinition(
        definition,
        downloadUrl: 'https://cdn.example/cyberpunk-neon.json',
        sha256Checksum: 'deadbeef',
      );

      expect(manifest.id, 'cyberpunk-neon');
      expect(manifest.name, 'Cyberpunk Neon');
      expect(manifest.type, ExtensionManifest.typeTheme);
      expect(manifest.version, '1.0.0');
      expect(manifest.downloadUrl, 'https://cdn.example/cyberpunk-neon.json');
      expect(manifest.sha256Checksum, 'deadbeef');
      expect(manifest.author, 'QueryaHub');
      expect(manifest.description, 'Neon theme');
      expect(manifest.homepage, 'https://example.com');
      expect(manifest.license, 'MIT');
      expect(manifest.preview, 'https://cdn.example/preview.png');
      expect(manifest.tags, ['neon']);
    });

    test('fromThemeDefinition falls back to content hash and 0.0.0 version',
        () {
      const definition = ThemeDefinition(
        id: 'minimal',
        name: 'Minimal',
        source: ThemeSource.builtin,
        format: ThemeFormat.queryaCustom,
        isDark: true,
        contentHash: 'ff00aa11',
      );

      final manifest = ExtensionManifest.fromThemeDefinition(definition);

      expect(manifest.version, '0.0.0');
      expect(manifest.sha256Checksum, 'ff00aa11');
      expect(manifest.downloadUrl, isEmpty);
    });

    group('id (#1560)', () {
      Map<String, dynamic> json(Object? id) =>
          {'id': id, 'name': 'X', 'type': 'theme'};

      test('accepts letters, digits, dots, dashes and underscores', () {
        for (final id in [
          'acme.redis-driver',
          'queryahub.clickhouse-driver',
          'my_theme',
          '42',
        ]) {
          expect(ExtensionManifest.fromJson(json(id)).id, id);
        }
      });

      test('rejects ids that are not a single folder name', () {
        for (final id in [
          '../x',
          '..',
          '.',
          'a/b',
          r'..\x',
          r'a\b',
          '/etc',
          r'C:\x',
          '',
          ' ',
          '.hidden',
          'a..b',
          'CON',
          'nul.txt',
          'a\x00b',
          'x' * 129,
          null,
          42,
        ]) {
          expect(
            () => ExtensionManifest.fromJson(json(id)),
            throwsFormatException,
            reason: 'id: $id',
          );
        }
      });

      test('extensionDirectory refuses an unsafe id', () {
        final root = Directory.systemTemp;
        expect(
          ExtensionPaths.extensionDirectory(root, 'acme.theme').path,
          p.join(root.path, 'acme.theme'),
        );
        for (final id in ['../x', '', '.', 'a/b']) {
          expect(
            () => ExtensionPaths.extensionDirectory(root, id),
            throwsArgumentError,
            reason: 'id: $id',
          );
        }
      });
    });
  });
}
