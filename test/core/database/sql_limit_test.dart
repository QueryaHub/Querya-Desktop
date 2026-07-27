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

    test('does not append LIMIT if LIMIT already exists', () {
      expect(
        injectSqlLimit('SELECT * FROM users LIMIT 10', 5000),
        'SELECT * FROM users LIMIT 10',
      );
      expect(
        injectSqlLimit('SELECT * FROM users limit 10;', 5000),
        'SELECT * FROM users limit 10;',
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
  });
}
