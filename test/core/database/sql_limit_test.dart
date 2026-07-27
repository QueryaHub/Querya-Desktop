import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';

void main() {
  group('injectSqlLimit', () {
    test('appends LIMIT to select query without limit', () {
      expect(
        injectSqlLimit('SELECT * FROM users', 5000),
        'SELECT * FROM users\nLIMIT 5000',
      );
    });

    test('handles trailing semicolons', () {
      expect(
        injectSqlLimit('SELECT * FROM users;', 5000),
        'SELECT * FROM users\nLIMIT 5000;',
      );
      expect(
        injectSqlLimit('SELECT * FROM users;  ', 5000),
        'SELECT * FROM users\nLIMIT 5000;',
      );
      expect(
        injectSqlLimit('SELECT * FROM users;;', 5000),
        'SELECT * FROM users\nLIMIT 5000;;',
      );
    });

    test('does not append LIMIT if LIMIT already exists and within cap', () {
      expect(
        injectSqlLimit('SELECT * FROM users LIMIT 10', 5000),
        'SELECT * FROM users LIMIT 10',
      );
      expect(
        injectSqlLimit('SELECT * FROM users limit 10;', 5000),
        'SELECT * FROM users limit 10;',
      );
    });

    test('clamps LIMIT larger than cap', () {
      expect(
        injectSqlLimit('SELECT * FROM users LIMIT 999999', 5000),
        'SELECT * FROM users LIMIT 5000',
      );
      expect(
        injectSqlLimit('SELECT * FROM users LIMIT 100000 OFFSET 20;', 1000),
        'SELECT * FROM users LIMIT 1000 OFFSET 20;',
      );
    });

    test('replaces LIMIT ALL with cap', () {
      expect(
        injectSqlLimit('SELECT * FROM users LIMIT ALL', 5000),
        'SELECT * FROM users LIMIT 5000',
      );
    });

    test('clamps FETCH FIRST n ROWS ONLY', () {
      expect(
        injectSqlLimit(
          'SELECT * FROM users FETCH FIRST 100000 ROWS ONLY',
          5000,
        ),
        'SELECT * FROM users FETCH FIRST 5000 ROWS ONLY',
      );
      expect(
        injectSqlLimit(
          'SELECT * FROM users FETCH FIRST 10 ROWS ONLY',
          5000,
        ),
        'SELECT * FROM users FETCH FIRST 10 ROWS ONLY',
      );
    });

    test('does not modify non-select/non-read queries', () {
      expect(
        injectSqlLimit('INSERT INTO users VALUES (1)', 5000),
        'INSERT INTO users VALUES (1)',
      );
      expect(
        injectSqlLimit('UPDATE users SET x = 1', 5000),
        'UPDATE users SET x = 1',
      );
      expect(
        injectSqlLimit('PRAGMA table_info(users)', 5000),
        'PRAGMA table_info(users)',
      );
    });

    test('appends LIMIT to WITH and VALUES', () {
      expect(
        injectSqlLimit(
          'WITH t AS (SELECT * FROM users) SELECT * FROM t;',
          5000,
        ),
        'WITH t AS (SELECT * FROM users) SELECT * FROM t\nLIMIT 5000;',
      );
      expect(
        injectSqlLimit('VALUES (1), (2), (3)', 2),
        'VALUES (1), (2), (3)\nLIMIT 2',
      );
    });

    test('ignores non-positive limit', () {
      expect(injectSqlLimit('SELECT 1', 0), 'SELECT 1');
      expect(injectSqlLimit('SELECT 1', -1), 'SELECT 1');
    });

    test('skips leading line comments when detecting SELECT', () {
      expect(
        injectSqlLimit('-- comment\nSELECT * FROM t', 100),
        '-- comment\nSELECT * FROM t\nLIMIT 100',
      );
    });

    test('does not clamp LIMIT text inside string literals', () {
      expect(
        injectSqlLimit(
          "SELECT * FROM t WHERE note = 'Use LIMIT 999999 rows'",
          5000,
        ),
        "SELECT * FROM t WHERE note = 'Use LIMIT 999999 rows'\nLIMIT 5000",
      );
      expect(
        injectSqlLimit(
          "SELECT * FROM t WHERE note = 'LIMIT 999999' LIMIT 999999",
          5000,
        ),
        "SELECT * FROM t WHERE note = 'LIMIT 999999' LIMIT 5000",
      );
    });

    test('does not treat LIMIT inside dollar quotes as a clause', () {
      expect(
        injectSqlLimit(
          r"SELECT $$LIMIT 999999$$ AS x FROM t",
          100,
        ),
        r"SELECT $$LIMIT 999999$$ AS x FROM t"
        '\nLIMIT 100',
      );
    });
  });
}
