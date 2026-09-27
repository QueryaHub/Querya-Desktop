import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sqlite_sql.dart';

void main() {
  group('sqliteSqlIsReadOnlyQuery', () {
    test('SELECT / VALUES / EXPLAIN are read-only', () {
      expect(sqliteSqlIsReadOnlyQuery('SELECT 1'), isTrue);
      expect(sqliteSqlIsReadOnlyQuery('  values (1)'), isTrue);
      expect(sqliteSqlIsReadOnlyQuery('EXPLAIN SELECT 1'), isTrue);
    });

    test('strips leading comments before the first keyword', () {
      expect(sqliteSqlIsReadOnlyQuery('-- c\nSELECT 1'), isTrue);
      expect(sqliteSqlIsReadOnlyQuery('/* c */ SELECT 1'), isTrue);
      expect(
        sqliteSqlIsReadOnlyQuery(
            '-- c\nWITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x'),
        isFalse,
      );
    });

    test('WITH SELECT / VALUES is read-only; WITH INSERT is a write', () {
      expect(
        sqliteSqlIsReadOnlyQuery('WITH x AS (SELECT 1) SELECT * FROM x'),
        isTrue,
      );
      expect(
        sqliteSqlIsReadOnlyQuery(
          'WITH x AS (SELECT 1), y AS (SELECT 2) SELECT * FROM x',
        ),
        isTrue,
      );
      expect(
        sqliteSqlIsReadOnlyQuery(
          'WITH RECURSIVE x(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM x WHERE n<3) SELECT * FROM x',
        ),
        isTrue,
      );
      expect(
        sqliteSqlIsReadOnlyQuery(
          'WITH x AS NOT MATERIALIZED (SELECT 1) SELECT * FROM x',
        ),
        isTrue,
      );
      expect(
        sqliteSqlIsReadOnlyQuery(
          'WITH x AS (SELECT 1) INSERT INTO t SELECT * FROM x',
        ),
        isFalse,
      );
      expect(
        sqliteSqlIsReadOnlyQuery(
          'WITH x AS (SELECT 1) UPDATE t SET a = 1',
        ),
        isFalse,
      );
    });

    test('PRAGMA query is read-only; assignment is a write', () {
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA busy_timeout'), isTrue);
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA table_info(users)'), isTrue);
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA busy_timeout=5000'), isFalse);
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA journal_mode=WAL'), isFalse);
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA journal_mode = WAL'), isFalse);
      expect(sqliteSqlIsReadOnlyQuery('PRAGMA foreign_keys=ON'), isFalse);
    });

    test('INSERT / CREATE are writes', () {
      expect(sqliteSqlIsReadOnlyQuery('INSERT INTO t VALUES (1)'), isFalse);
      expect(sqliteSqlIsReadOnlyQuery('CREATE TABLE t (id INT)'), isFalse);
    });
  });

  group('sqliteHasMultipleStatements', () {
    test('single statement, with or without a trailing semicolon', () {
      expect(sqliteHasMultipleStatements('SELECT 1'), isFalse);
      expect(sqliteHasMultipleStatements('SELECT 1;'), isFalse);
      expect(sqliteHasMultipleStatements('SELECT 1;  '), isFalse);
      expect(sqliteHasMultipleStatements('SELECT 1;;'), isFalse);
    });

    test('a second statement after a top-level semicolon is detected', () {
      expect(
        sqliteHasMultipleStatements('SELECT 1 WHERE 0; DELETE FROM t'),
        isTrue,
      );
      expect(
        sqliteHasMultipleStatements('SELECT 1; SELECT 2;'),
        isTrue,
      );
    });

    test('a semicolon inside a string / quoted identifier does not count',
        () {
      expect(
        sqliteHasMultipleStatements("SELECT 'a;b'"),
        isFalse,
      );
      expect(
        sqliteHasMultipleStatements('SELECT "a;b" FROM t'),
        isFalse,
      );
      expect(
        sqliteHasMultipleStatements('SELECT * FROM [a;b]'),
        isFalse,
      );
      // A doubled quote (escaped) inside the literal, followed by a real
      // top-level `;` and a second statement, is still detected.
      expect(
        sqliteHasMultipleStatements("SELECT 'it''s; fine'; DELETE FROM t"),
        isTrue,
      );
    });

    test('a semicolon inside a comment does not count', () {
      expect(
        sqliteHasMultipleStatements('SELECT 1 -- ; not real\n'),
        isFalse,
      );
      expect(
        sqliteHasMultipleStatements('SELECT 1 /* ; not real */'),
        isFalse,
      );
    });
  });
}
