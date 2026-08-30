import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/connection_type.dart';
import 'package:querya_desktop/core/database/connection_type_choice.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';

void main() {
  group('ConnectionType', () {
    test('covers SQL and NoSQL classifications', () {
      expect(ConnectionType.postgresql.isSql, isTrue);
      expect(ConnectionType.mysql.isSql, isTrue);
      expect(ConnectionType.sqlite.isSql, isTrue);
      expect(ConnectionType.redis.isSql, isFalse);
      expect(ConnectionType.mongodb.isSql, isFalse);

      expect(ConnectionType.redis.isNoSql, isTrue);
      expect(ConnectionType.mongodb.isNoSql, isTrue);
      expect(ConnectionType.postgresql.isNoSql, isFalse);
      expect(ConnectionType.mysql.isNoSql, isFalse);
      expect(ConnectionType.sqlite.isNoSql, isFalse);
    });

    test('provides human-readable labels', () {
      expect(ConnectionType.postgresql.label, 'PostgreSQL');
      expect(ConnectionType.mysql.label, 'MySQL');
      expect(ConnectionType.sqlite.label, 'SQLite');
      expect(ConnectionType.redis.label, 'Redis');
      expect(ConnectionType.mongodb.label, 'MongoDB');
    });
  });

  group('ConnectionTypeChoice', () {
    test('BuiltInConnectionType equality and properties', () {
      const a = BuiltInConnectionType(ConnectionType.postgresql);
      const b = BuiltInConnectionType(ConnectionType.postgresql);
      const c = BuiltInConnectionType(ConnectionType.mysql);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.label, 'PostgreSQL');
    });

    test('ExtensionDriverChoice equality and properties', () {
      const m1 = ExtensionManifest(
        id: 'pkg.clickhouse',
        name: 'ClickHouse Plugin',
        version: '1.0.0',
        publisher: 'QueryaHub',
        type: ExtensionType.databaseDriver,
        engines: {},
      );
      const d1 = DriverContribution(
        driverId: 'clickhouse',
        displayName: 'ClickHouse',
      );
      const d2 = DriverContribution(
        driverId: 'clickhouse-cluster',
        displayName: 'ClickHouse Cluster',
      );

      const choice1 = ExtensionDriverChoice(manifest: m1, driver: d1);
      const choice2 = ExtensionDriverChoice(manifest: m1, driver: d1);
      const choice3 = ExtensionDriverChoice(manifest: m1, driver: d2);

      expect(choice1, equals(choice2));
      expect(choice1.hashCode, equals(choice2.hashCode));
      expect(choice1, isNot(equals(choice3)));
      expect(choice1.label, 'ClickHouse');
    });
  });
}
