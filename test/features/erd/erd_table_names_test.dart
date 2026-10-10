import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_table_names.dart';

void main() {
  group('ErdTableNames', () {
    test('postgres splits schema.table and quotes each part', () {
      expect(ErdTableNames.split('sales.orders', SqlDialect.postgres),
          ('sales', 'orders'));
      expect(ErdTableNames.split('orders', SqlDialect.postgres),
          (null, 'orders'));
      expect(ErdTableNames.qualifiedSql('sales.orders', SqlDialect.postgres),
          '"sales"."orders"');
      expect(ErdTableNames.qualifiedSql('a"b', SqlDialect.postgres), '"a""b"');
    });

    test('mysql and sqlite keep a dot as part of the name', () {
      expect(ErdTableNames.split('a.b', SqlDialect.mysql), (null, 'a.b'));
      expect(ErdTableNames.qualifiedSql('a.b', SqlDialect.mysql), '`a.b`');
      expect(ErdTableNames.selectSql('users', SqlDialect.sqlite),
          'SELECT * FROM "users" LIMIT 100;');
    });

    test('schema objects match the Quick Switcher ones', () {
      final other = ErdTableNames.schemaObject('sales.orders',
          SqlDialect.postgres, database: 'shop');
      expect(other.schema, 'sales');
      expect(other.name, 'orders');
      expect(other.database, 'shop');
      expect(other.kind, QueryaSchemaObjectKind.table);

      final current = ErdTableNames.schemaObject('orders', SqlDialect.postgres,
          database: 'shop');
      expect(current.schema, ErdTableNames.defaultPostgresSchema);

      final mysql = ErdTableNames.schemaObject('order.items', SqlDialect.mysql,
          database: 'shop');
      expect(mysql.name, 'order.items');
      expect(mysql.database, 'shop');

      final sqlite = ErdTableNames.schemaObject('users', SqlDialect.sqlite,
          database: '');
      expect(sqlite.name, 'users');
      expect(sqlite.schema, isNull);
    });
  });
}
