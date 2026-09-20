import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/mysql/mysql_table_utils.dart';

void main() {
  group('isAllowedMysqlSelectQuery', () {
    test('allows single SELECT', () {
      expect(isAllowedMysqlSelectQuery('SELECT * FROM t'), isTrue);
    });

    test('allows WITH', () {
      expect(isAllowedMysqlSelectQuery('WITH x AS (SELECT 1) SELECT * FROM x'),
          isTrue);
    });

    test('rejects multi-statement', () {
      expect(isAllowedMysqlSelectQuery('SELECT 1; SELECT 2'), isFalse);
    });

    test('rejects empty', () {
      expect(isAllowedMysqlSelectQuery(''), isFalse);
    });

    test('allows semicolon inside single-quoted string', () {
      expect(
        isAllowedMysqlSelectQuery(
          "SELECT * FROM logs WHERE message = 'error; system halted'",
        ),
        isTrue,
      );
    });

    test('allows semicolon inside double-quoted string', () {
      expect(
        isAllowedMysqlSelectQuery(
          'SELECT * FROM users WHERE status = "active; verified"',
        ),
        isTrue,
      );
    });

    test('allows trailing semicolon on single statement', () {
      expect(isAllowedMysqlSelectQuery('SELECT * FROM t;'), isTrue);
    });

    test('allows trailing line comment after semicolon', () {
      expect(isAllowedMysqlSelectQuery('SELECT * FROM t; -- done'), isTrue);
    });

    test('allows semicolon inside block comment', () {
      expect(
        isAllowedMysqlSelectQuery(
          'SELECT 1 /* note; ignored */ FROM t',
        ),
        isTrue,
      );
    });

    test('rejects INTO OUTFILE', () {
      expect(
        isAllowedMysqlSelectQuery(
          "SELECT * FROM users INTO OUTFILE '/tmp/users.txt'",
        ),
        isFalse,
      );
    });

    test('rejects FOR UPDATE', () {
      expect(
        isAllowedMysqlSelectQuery('SELECT * FROM accounts FOR UPDATE'),
        isFalse,
      );
    });

    test('allows INTO OUTFILE inside string literal', () {
      expect(
        isAllowedMysqlSelectQuery(
          "SELECT * FROM docs WHERE body = 'INTO OUTFILE example'",
        ),
        isTrue,
      );
    });

    test('rejects non-SELECT statements', () {
      expect(isAllowedMysqlSelectQuery('DELETE FROM t'), isFalse);
    });
  });

  group('mysqlBrowseDataSql', () {
    test('orders by quoted PK columns', () {
      expect(
        mysqlBrowseDataSql(
          qualifiedFrom: '`shop`.`orders`',
          primaryKeys: const ['id'],
          limit: 200,
          offset: 400,
        ),
        'SELECT * FROM `shop`.`orders` ORDER BY `id` LIMIT 200 OFFSET 400',
      );
    });

    test('composite PK lists all columns', () {
      expect(
        mysqlBrowseDataSql(
          qualifiedFrom: '`db`.`t`',
          primaryKeys: const ['a', 'b'],
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM `db`.`t` ORDER BY `a`, `b` LIMIT 200 OFFSET 0',
      );
    });

    test('omits ORDER BY when there is no PK', () {
      expect(
        mysqlBrowseDataSql(
          qualifiedFrom: '`db`.`v`',
          primaryKeys: const [],
          limit: 200,
          offset: 0,
        ),
        'SELECT * FROM `db`.`v` LIMIT 200 OFFSET 0',
      );
    });
  });
}
