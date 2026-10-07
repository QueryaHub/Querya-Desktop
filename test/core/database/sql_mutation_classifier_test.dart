import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_mutation_classifier.dart';

void main() {
  group('isMutatingSqlStatement', () {
    test('data changes', () {
      for (final sql in [
        "INSERT INTO t VALUES (1)",
        "  update t set a = 1",
        "DELETE FROM t",
        "REPLACE INTO t VALUES (1)",
        "MERGE INTO t USING s ON (t.id = s.id) WHEN MATCHED THEN DELETE",
        "TRUNCATE TABLE t",
      ]) {
        expect(isMutatingSqlStatement(sql), isTrue, reason: sql);
      }
    });

    test('schema changes', () {
      for (final sql in [
        'DROP TABLE t',
        'ALTER TABLE t ADD COLUMN c int',
        'CREATE INDEX i ON t (a)',
        'RENAME TABLE a TO b',
        'GRANT SELECT ON t TO u',
        'REVOKE ALL ON t FROM u',
      ]) {
        expect(isMutatingSqlStatement(sql), isTrue, reason: sql);
      }
    });

    test('reads are not mutations', () {
      for (final sql in [
        'SELECT * FROM t',
        'select 1',
        'EXPLAIN SELECT 1',
        'SHOW TABLES',
        'WITH x AS (SELECT 1) SELECT * FROM x',
        '',
        '   ',
      ]) {
        expect(isMutatingSqlStatement(sql), isFalse, reason: sql);
      }
    });

    test('data-modifying CTEs count', () {
      expect(
        isMutatingSqlStatement(
            'WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d'),
        isTrue,
      );
    });

    test('keywords in comments and strings are ignored', () {
      expect(isMutatingSqlStatement("-- DELETE FROM t\nSELECT 1"), isFalse);
      expect(isMutatingSqlStatement("/* DROP */ SELECT 'update me'"), isFalse);
      expect(isMutatingSqlStatement("/* note */ UPDATE t SET a = 1"), isTrue);
    });
  });

  group('containsMutatingSql', () {
    test('finds a mutation anywhere in a script', () {
      expect(containsMutatingSql('SELECT 1; DELETE FROM t WHERE id = 1;'),
          isTrue);
    });

    test('read-only scripts are not mutations', () {
      expect(containsMutatingSql('SELECT 1; SELECT 2;'), isFalse);
      expect(containsMutatingSql("SELECT 'a;DELETE FROM t'"), isFalse);
    });
  });
}
