import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

void main() {
  group('ExtensionManifest', () {
    test('parses valid manifest correctly', () {
      final json = {
        'id': 'queryahub.clickhouse-driver',
        'name': 'ClickHouse Database Driver',
        'version': '1.0.0',
        'publisher': 'QueryaHub',
        'type': 'database_driver',
        'engines': {
          'querya_desktop': '^0.5.0'
        },
        'main': 'bin/clickhouse_plugin',
        'icon': 'assets/icon.svg',
        'description': 'Full support for ClickHouse databases'
      };

      final manifest = ExtensionManifest.fromJson(json);

      expect(manifest.id, 'queryahub.clickhouse-driver');
      expect(manifest.name, 'ClickHouse Database Driver');
      expect(manifest.version, '1.0.0');
      expect(manifest.publisher, 'QueryaHub');
      expect(manifest.type, ExtensionType.databaseDriver);
      expect(manifest.engines, {'querya_desktop': '^0.5.0'});
      expect(manifest.main, 'bin/clickhouse_plugin');
      expect(manifest.icon, 'assets/icon.svg');
      expect(manifest.description, 'Full support for ClickHouse databases');
    });

    test('handles missing optional fields', () {
      final json = {
        'id': 'queryahub.my-theme',
        'name': 'My Theme',
        'version': '1.0.0',
        'publisher': 'QueryaHub',
        'type': 'theme',
        'engines': {
          'querya_desktop': '^0.5.0'
        }
      };

      final manifest = ExtensionManifest.fromJson(json);

      expect(manifest.id, 'queryahub.my-theme');
      expect(manifest.type, ExtensionType.theme);
      expect(manifest.main, isNull);
      expect(manifest.icon, isNull);
      expect(manifest.description, isNull);
    });

    test('falls back to unknown type for unrecognized extension types', () {
      final json = {
        'id': 'queryahub.future-plugin',
        'name': 'Future Plugin',
        'version': '1.0.0',
        'publisher': 'QueryaHub',
        'type': 'future_formatter',
        'engines': {}
      };

      final manifest = ExtensionManifest.fromJson(json);

      expect(manifest.type, ExtensionType.unknown);
    });

    test('throws type error on completely invalid json structure', () {
      final json = {
        'id': 'missing_everything_else'
      };

      expect(() => ExtensionManifest.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
