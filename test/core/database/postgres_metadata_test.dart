import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/postgres_metadata.dart';

void main() {
  group('PgIndexRow', () {
    test('stores fields and supports const canonical equality', () {
      const row = PgIndexRow(
        tableName: 'orders',
        indexName: 'orders_pkey',
        indexDef: 'CREATE UNIQUE INDEX ...',
        sizeBytes: 8192,
      );
      expect(row.tableName, 'orders');
      expect(row.indexName, 'orders_pkey');
      expect(row.indexDef, contains('CREATE'));
      expect(row.sizeBytes, 8192);

      const same = PgIndexRow(
        tableName: 'orders',
        indexName: 'orders_pkey',
        indexDef: 'CREATE UNIQUE INDEX ...',
        sizeBytes: 8192,
      );
      expect(identical(row, same), isTrue);
    });

    test('sizeBytes may be null', () {
      const row = PgIndexRow(
        tableName: 't',
        indexName: 'i',
        indexDef: 'CREATE INDEX ...',
      );
      expect(row.sizeBytes, isNull);
    });
  });

  group('PgTriggerRow', () {
    test('stores fields', () {
      const row = PgTriggerRow(
        tableName: 'users',
        triggerName: 'tr_users',
        definition: 'CREATE TRIGGER ...',
      );
      expect(row.tableName, 'users');
      expect(row.triggerName, 'tr_users');
      expect(row.definition, contains('TRIGGER'));
    });
  });

  group('PgTypeRow', () {
    test('stores name and kind', () {
      const row = PgTypeRow(name: 'status_t', kind: 'enum');
      expect(row.name, 'status_t');
      expect(row.kind, 'enum');
    });
  });

  group('PgExtensionRow', () {
    test('stores name and version', () {
      const row = PgExtensionRow(name: 'plpgsql', version: '1.0');
      expect(row.name, 'plpgsql');
      expect(row.version, '1.0');
    });
  });

  group('PgFdwRow', () {
    test('handler is optional', () {
      const withHandler = PgFdwRow(name: 'postgres_fdw', handler: 'handler_fn');
      expect(withHandler.name, 'postgres_fdw');
      expect(withHandler.handler, 'handler_fn');

      const bare = PgFdwRow(name: 'dummy');
      expect(bare.handler, isNull);
    });
  });

  group('PgForeignServerRow', () {
    test('stores server and FDW name', () {
      const row = PgForeignServerRow(serverName: 'remote_pg', fdwName: 'postgres_fdw');
      expect(row.serverName, 'remote_pg');
      expect(row.fdwName, 'postgres_fdw');
    });
  });

  group('PgTablePrivilegeRow', () {
    test('stores grant-style fields', () {
      const row = PgTablePrivilegeRow(
        grantee: 'app_role',
        privilegeType: 'SELECT',
        isGrantable: 'YES',
      );
      expect(row.grantee, 'app_role');
      expect(row.privilegeType, 'SELECT');
      expect(row.isGrantable, 'YES');
    });
  });
}
