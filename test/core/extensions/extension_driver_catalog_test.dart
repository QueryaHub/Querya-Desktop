import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/extension_connection_form.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';

void main() {
  group('ExtensionDriverCatalog', () {
    test('built-ins cover five drivers', () {
      expect(ExtensionDriverCatalog.builtInChoices, hasLength(5));
      expect(
        ExtensionDriverCatalog.builtInChoices
            .whereType<BuiltInConnectionType>()
            .map((c) => c.type),
        containsAll([
          ConnectionType.postgresql,
          ConnectionType.mysql,
          ConnectionType.sqlite,
          ConnectionType.redis,
          ConnectionType.mongodb,
        ]),
      );
    });
  });

  group('connectionRowFromExtensionForm', () {
    test('maps host/port/username and stores extras in driverOptions', () {
      final manifest = ExtensionManifest(
        id: 'queryahub.clickhouse-driver',
        name: 'ClickHouse',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: const {},
        installPath: '/tmp/ext',
      );
      const driver = DriverContribution(
        driverId: 'clickhouse',
        displayName: 'ClickHouse',
        defaultPort: 8123,
      );

      final row = connectionRowFromExtensionForm(
        manifest: manifest,
        driver: driver,
        name: 'Local CH',
        values: {
          'host': '127.0.0.1',
          'port': 8123,
          'username': 'querya',
          'password': 'secret',
          'sslMode': 'prefer',
          'safe_mode': true,
        },
      );

      expect(row.type, 'clickhouse');
      expect(row.extensionId, 'queryahub.clickhouse-driver');
      expect(row.host, '127.0.0.1');
      expect(row.port, 8123);
      expect(row.username, 'querya');
      expect(row.password, 'secret');
      expect(row.useSSL, isTrue);
      expect(row.isExtensionDriver, isTrue);
      expect(row.driverOptions, contains('sslMode'));
      expect(row.driverOptions, contains('safe_mode'));
      expect(row.driverOptions, isNot(contains('password')));
    });
  });

  group('ConnectionTypeChoice equality', () {
    test('built-ins compare by enum', () {
      expect(
        const BuiltInConnectionType(ConnectionType.mysql),
        const BuiltInConnectionType(ConnectionType.mysql),
      );
    });

    test('extension choices compare by package + driverId', () {
      final m = ExtensionManifest(
        id: 'pkg.a',
        name: 'A',
        version: '1',
        publisher: 'p',
        type: ExtensionType.databaseDriver,
        engines: const {},
      );
      const d = DriverContribution(driverId: 'x', displayName: 'X');
      expect(
        ExtensionDriverChoice(manifest: m, driver: d),
        ExtensionDriverChoice(manifest: m, driver: d),
      );
    });
  });
}
