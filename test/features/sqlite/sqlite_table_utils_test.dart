import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';

void main() {
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

    test('orders by rowid when a table has no PK', () {
      expect(
        sqliteBrowseDataSql(
          qualifiedFrom: '"t"',
          primaryKeys: const [],
          isView: false,
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM "t" ORDER BY "rowid" LIMIT 200 OFFSET 0',
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
