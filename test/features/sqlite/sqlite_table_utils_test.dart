import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';

void main() {
  group('sqliteTableBrowserPrimaryKeys', () {
    test('keeps a declared PRIMARY KEY', () {
      expect(
        sqliteTableBrowserPrimaryKeys(
          declaredPrimaryKeys: const ['id'],
          isView: false,
        ),
        ['id'],
      );
    });

    test('uses rowid when a table has no declared PK', () {
      expect(
        sqliteTableBrowserPrimaryKeys(
          declaredPrimaryKeys: const [],
          isView: false,
        ),
        ['rowid'],
      );
    });

    test('stays empty for views', () {
      expect(
        sqliteTableBrowserPrimaryKeys(
          declaredPrimaryKeys: const [],
          isView: true,
        ),
        isEmpty,
      );
    });
  });

  group('sqliteBrowseOrderColumns', () {
    test('uses declared PK columns', () {
      expect(
        sqliteBrowseOrderColumns(
          primaryKeys: const ['id'],
          isView: false,
        ),
        ['id'],
      );
    });

    test('uses rowid when a table has no PK', () {
      expect(
        sqliteBrowseOrderColumns(
          primaryKeys: const [],
          isView: false,
        ),
        ['rowid'],
      );
    });

    test('omits order columns for views', () {
      expect(
        sqliteBrowseOrderColumns(
          primaryKeys: const [],
          isView: true,
        ),
        isEmpty,
      );
    });
  });

  group('sqliteBrowseDataSql', () {
    test('orders by quoted PK columns', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"orders"',
          primaryKeys: const ['id'],
          isView: false,
          limit: 200,
          offset: 400,
        ),
        'SELECT * FROM "orders" ORDER BY "id" LIMIT 200 OFFSET 400',
      );
    });

    test('composite PK lists all columns', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"t"',
          primaryKeys: const ['a', 'b'],
          isView: false,
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM "t" ORDER BY "a", "b" LIMIT 200 OFFSET 0',
      );
    });

    test('projects rowid and orders by it when a table has no PK', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"t"',
          primaryKeys: const [],
          isView: false,
          limit: 200,
          offset: 0,
        ),
        'SELECT "rowid", * FROM "t" ORDER BY "rowid" LIMIT 200 OFFSET 0',
      );
    });

    test('projects rowid when PK was resolved to implicit rowid', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"t"',
          primaryKeys: const ['rowid'],
          isView: false,
          limit: 200,
          offset: 0,
        ),
        'SELECT "rowid", * FROM "t" ORDER BY "rowid" LIMIT 200 OFFSET 0',
      );
    });

    test('omits ORDER BY for views', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"v"',
          primaryKeys: const [],
          isView: true,
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM "v" LIMIT 200 OFFSET 0',
      );
    });
  });
}
