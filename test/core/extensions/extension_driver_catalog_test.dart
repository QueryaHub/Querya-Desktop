import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/connection_type.dart';
import 'package:querya_desktop/core/database/connection_type_choice.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/features/connections/extension_connection_form.dart';

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
      const manifest = ExtensionManifest(
        id: 'queryahub.clickhouse-driver',
        name: 'ClickHouse',
        version: '1.0.0',
        publisher: 'Test',
        type: ExtensionType.databaseDriver,
        engines: {},
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
      expect(row.driverOptions, contains('safe_mode'));
      expect(row.driverOptions, isNot(contains('password')));
      expect(row.driverOptions, isNot(contains('sslMode')));
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
      const m = ExtensionManifest(
        id: 'pkg.a',
        name: 'A',
        version: '1',
        publisher: 'p',
        type: ExtensionType.databaseDriver,
        engines: {},
      );
      const d = DriverContribution(driverId: 'x', displayName: 'X');
      expect(
        const ExtensionDriverChoice(manifest: m, driver: d),
        const ExtensionDriverChoice(manifest: m, driver: d),
      );
    });
  });
}
