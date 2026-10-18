import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/query_error_text.dart';

void main() {
  _positionTests();
  group('QueryErrorText (#1557)', () {
    // The example from the issue, as sqflite_common_ffi prints it.
    const sqlite =
        'SqliteFfiException(sqlite_error: 1, , SqliteException(1): while preparing '
        'statement, no such column: u.name, SQL logic error (code 1)\n'
        '  Causing statement (at position 29): SELECT * FROM (\n'
        'SELECT o.id, u.name FROM orders o JOIN users u ON u.id = o.user_id '
        'ORDER BY o.id LIMIT 200\n'
        ')\n'
        'LIMIT 5000}) DatabaseException(SqliteException(1): while preparing '
        'statement, no such column: u.name, SQL logic error (code 1)\n'
        '  Causing statement (at position 29): SELECT * FROM (\n'
        'SELECT o.id, u.name FROM orders o JOIN users u ON u.id = o.user_id '
        'ORDER BY o.id LIMIT 200\n'
        ')';

    test('SQLite: the message alone, without the wrapper or its position', () {
      final e = QueryErrorText.parse(sqlite);
      expect(e.summary, 'no such column: u.name');
      expect(e.hasDetail, isTrue);
      expect(e.detail, isNot(contains('SELECT * FROM (')));
      expect(e.detail, isNot(contains('LIMIT 5000')));
      expect(e.detail, isNot(contains('at position')));
      expect(e.detail, contains('ORDER BY o.id LIMIT 200'));
      expect(e.detail, contains('no such column: u.name'));
    });

    test('PostgreSQL: the server message, without detail and hint', () {
      final e = QueryErrorText.parse(
        'Severity.error 42703: column "nme" does not exist hint: Perhaps you meant "name".',
      );
      expect(e.summary, 'column "nme" does not exist');
      expect(e.detail, contains('hint: Perhaps'));
    });

    test('MySQL: the server message after the error code', () {
      final e = QueryErrorText.parse(
        "MySQLServerException [1054]: Unknown column 'nme' in 'field list'",
      );
      expect(e.summary, "Unknown column 'nme' in 'field list'");
    });

    test('anything else: its first line; one line has no extra detail', () {
      final one = QueryErrorText.parse('connection refused');
      expect(one.summary, 'connection refused');
      expect(one.hasDetail, isFalse);

      final two = QueryErrorText.parse('Exception: socket closed\nat line 3');
      expect(two.summary, 'socket closed');
      expect(two.hasDetail, isTrue);
    });

    test('text without the wrapper is left as it is', () {
      const raw = 'SqliteException(1): while preparing statement, near "SELEC": '
          'syntax error, SQL logic error (code 1)\n'
          '  Causing statement (at position 0): SELEC 1';
      final e = QueryErrorText.parse(raw);
      expect(e.summary, 'near "SELEC": syntax error');
      expect(e.detail, raw);
    });

    test('a very long message is cut in the summary only', () {
      final long = 'x' * 1000;
      final e = QueryErrorText.parse(long);
      expect(e.summary.length, lessThan(320));
      expect(e.detail, long);
    });
  });
}

void _positionTests() {
  group('where the error is in the user\'s SQL (#1557)', () {
    String sqliteError(String wrappedSql, int at) =>
        'SqliteFfiException(sqlite_error: 1, , SqliteException(1): while '
        'preparing statement, no such column: x, SQL logic error (code 1)\n'
        '  Causing statement (at position $at): $wrappedSql})';

    test('SQLite: the wrapper prefix is taken off', () {
      const sql = 'SELECT a, nope FROM t';
      final error = sqliteError('SELECT * FROM (\n$sql\n)\nLIMIT 5000', 16 + 10);
      expect(QueryErrorText.offsetIn(error, sql), 10);
      expect(sql.substring(10, 14), 'nope');
    });

    test('SQLite: without the wrapper the offset is the position', () {
      const sql = 'UPDATE t SET nope = 1';
      final error = sqliteError(sql, 13);
      expect(QueryErrorText.offsetIn(error, sql), 13);
    });

    test('SQLite counts bytes, the editor counts characters', () {
      const sql = "SELECT 'héllo', nope FROM t";
      // `é` is two bytes: `nope` starts at character 16, byte 17.
      final error = sqliteError('SELECT * FROM (\n$sql\n)', 16 + 17);
      expect(QueryErrorText.offsetIn(error, sql), 16);
      expect(sql.substring(16, 20), 'nope');
    });

    test('a position outside the text, or none, gives no offset', () {
      expect(QueryErrorText.offsetIn(sqliteError('SELECT 1', 500), 'SELECT 1'),
          isNull);
      expect(
          QueryErrorText.offsetIn(
              Exception('MySQLServerException [1064]: syntax error'), 'SELECT'),
          isNull);
    });

    test('PostgreSQL positions are 1-based characters', () {
      const sql = 'SELECT nope FROM t';
      expect(QueryErrorText.offsetOfPgPosition(8, sql), 7);
      expect(sql.substring(7, 11), 'nope');
      expect(QueryErrorText.offsetOfPgPosition(null, sql), isNull);
      expect(QueryErrorText.offsetOfPgPosition(0, sql), isNull);
      expect(QueryErrorText.offsetOfPgPosition(99, sql), isNull);
    });
  });
}
