import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';

void main() {
  group('ExtensionManifest', () {
    test('parses valid manifest correctly', () {
      final json = {
        'id': 'queryahub.clickhouse-driver',
        'name': 'ClickHouse Database Driver',
        'version': '1.0.0',
        'publisher': 'QueryaHub',
        'type': 'database_driver',
        'engines': {'querya_desktop': '^0.5.0'},
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
        'engines': {'querya_desktop': '^0.5.0'}
      };

      final manifest = ExtensionManifest.fromJson(json);

      expect(manifest.id, 'queryahub.my-theme');
      expect(manifest.type, ExtensionType.theme);
      expect(manifest.main, isNull);
      expect(manifest.icon, isNull);
      expect(manifest.description, isNull);
      expect(manifest.capabilities, isNull);
      expect(manifest.contributions, isNull);
    });

    test('parses capabilities and contributions (ClickHouse-like)', () {
      final json = {
        'id': 'queryahub.clickhouse-driver',
        'name': 'ClickHouse Database Driver (Analyst Edition)',
        'version': '1.0.0',
        'publisher': 'Querya Community',
        'type': 'database_driver',
        'engines': {'querya_desktop': '^2.0.0'},
        'main': 'bin/clickhouse_rpc_server',
        'icon': 'assets/icon.svg',
        'description': 'ClickHouse driver',
        'capabilities': {
          'databaseDriver': true,
          'sduiForms': true,
        },
        'sandbox': {
          'engine': 'process',
          'permissions': {
            'network': {'mode': 'connection_host_only', 'allow_ssl': true},
            'filesystem': {'scratch_mb': 100, 'access': 'scratch_only'},
            'resources': {'memory_mb': 256, 'max_open_files': 64},
          },
        },
        'contributions': {
          'drivers': [
            {
              'driverId': 'clickhouse',
              'displayName': 'ClickHouse (Analyst Edition)',
              'defaultPort': 8123,
              'connectionFormSchema': 'assets/connection_form.json',
            }
          ]
        },
      };

      final manifest = ExtensionManifest.fromJson(json);

      expect(manifest.capabilities?.databaseDriver, isTrue);
      expect(manifest.capabilities?.sduiForms, isTrue);
      expect(manifest.contributedDrivers, hasLength(1));
      final driver = manifest.contributedDrivers.first;
      expect(driver.driverId, 'clickhouse');
      expect(driver.displayName, 'ClickHouse (Analyst Edition)');
      expect(driver.defaultPort, 8123);
      expect(driver.connectionFormSchema, 'assets/connection_form.json');
      expect(manifest.sandbox?.engine, SandboxEngine.process);
    });

    test('toJson round-trips contributions and capabilities', () {
      final original = {
        'id': 'queryahub.clickhouse-driver',
        'name': 'ClickHouse',
        'version': '1.0.0',
        'publisher': 'Querya Community',
        'type': 'database_driver',
        'engines': {'querya_desktop': '^2.0.0'},
        'main': 'bin/clickhouse_rpc_server',
        'capabilities': {
          'databaseDriver': true,
          'sduiForms': true,
        },
        'contributions': {
          'drivers': [
            {
              'driverId': 'clickhouse',
              'displayName': 'ClickHouse',
              'defaultPort': 8123,
              'connectionFormSchema': 'assets/connection_form.json',
            }
          ]
        },
      };

      final manifest = ExtensionManifest.fromJson(original);
      final encoded = manifest.toJson();
      expect(encoded['capabilities'], isA<Map>());
      expect(encoded['contributions'], isA<Map>());

      final again = ExtensionManifest.fromJson(encoded);
      expect(again.capabilities?.databaseDriver, isTrue);
      expect(again.contributedDrivers.first.driverId, 'clickhouse');
      expect(
        again.contributedDrivers.first.connectionFormSchema,
        'assets/connection_form.json',
      );
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
      final json = {'id': 'missing_everything_else'};

      expect(() => ExtensionManifest.fromJson(json), throwsA(isA<TypeError>()));
    });
  });
}
