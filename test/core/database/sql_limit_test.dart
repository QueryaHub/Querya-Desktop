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

    group('leading comments', () {
      test('block comment before SELECT still gets a LIMIT', () {
        expect(
          injectSqlLimit('/* Sales report */ SELECT * FROM large_orders;', 100),
          '/* Sales report */ SELECT * FROM large_orders\nLIMIT 100;',
        );
      });

      test('multi-line, nested and mixed leading comments are skipped', () {
        expect(
          injectSqlLimit('/* a\n b /* nested */ c */\n-- x\nSELECT 1', 100),
          '/* a\n b /* nested */ c */\n-- x\nSELECT 1\nLIMIT 100',
        );
      });

      test('leading block comment does not make non-select queries limited',
          () {
        expect(
          injectSqlLimit('/* c */ UPDATE users SET x = 1', 100),
          '/* c */ UPDATE users SET x = 1',
        );
      });

      test('stripLeadingWhitespaceAndLineComments also strips block comments',
          () {
        expect(
          stripLeadingWhitespaceAndLineComments('/* c */ \n SELECT 1'),
          'SELECT 1',
        );
        expect(stripLeadingWhitespaceAndLineComments('/* unterminated'), '');
      });
    });

    group('outer query targeting', () {
      test('CTE LIMIT within cap does not stop the outer query being capped',
          () {
        const sql = 'WITH top AS (SELECT id FROM customers LIMIT 10) '
            'SELECT * FROM orders JOIN top ON orders.c = top.id';
        expect(injectSqlLimit(sql, 5000), '$sql\nLIMIT 5000');
      });

      test('oversized CTE LIMIT is left intact and the outer query is capped',
          () {
        const sql = 'WITH top AS (SELECT id FROM customers LIMIT 10000) '
            'SELECT * FROM orders';
        expect(injectSqlLimit(sql, 5000), '$sql\nLIMIT 5000');
      });

      test('subquery FETCH FIRST is ignored for the outer query', () {
        const sql =
            'SELECT * FROM (SELECT id FROM t FETCH FIRST 5 ROWS ONLY) x';
        expect(injectSqlLimit(sql, 100), '$sql\nLIMIT 100');
      });

      test('outer LIMIT is clamped, not the CTE one', () {
        expect(
          injectSqlLimit(
            'WITH t AS (SELECT 1 LIMIT 10000) SELECT * FROM t LIMIT 99999',
            5000,
          ),
          'WITH t AS (SELECT 1 LIMIT 10000) SELECT * FROM t LIMIT 5000',
        );
      });

      test('outer LIMIT within cap after a CTE LIMIT is left unchanged', () {
        const sql = 'WITH t AS (SELECT 1 LIMIT 10000) SELECT * FROM t LIMIT 20';
        expect(injectSqlLimit(sql, 5000), sql);
      });

      test('outer LIMIT ALL is replaced', () {
        expect(
          injectSqlLimit(
              'WITH t AS (SELECT 1 LIMIT 3) SELECT * FROM t LIMIT ALL', 50),
          'WITH t AS (SELECT 1 LIMIT 3) SELECT * FROM t LIMIT 50',
        );
      });
    });

    group('comments and literals', () {
      test('LIMIT text inside comments or strings is ignored', () {
        expect(
          injectSqlLimit(
              "SELECT 'LIMIT 1' AS s -- LIMIT 2\nFROM t /* LIMIT 3 */", 100),
          "SELECT 'LIMIT 1' AS s -- LIMIT 2\nFROM t\nLIMIT 100 /* LIMIT 3 */",
        );
      });

      test('trailing line comment does not swallow the injected LIMIT', () {
        expect(
          injectSqlLimit('SELECT * FROM t; -- done', 100),
          'SELECT * FROM t\nLIMIT 100; -- done',
        );
        expect(
          injectSqlLimit('SELECT * FROM t -- note', 100),
          'SELECT * FROM t\nLIMIT 100 -- note',
        );
      });
    });
  });
}
