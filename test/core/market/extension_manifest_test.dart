import 'package:flutter_test/flutter_test.dart';
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

    test('fromThemeDefinition falls back to content hash and 0.0.0 version', () {
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
  });
}
