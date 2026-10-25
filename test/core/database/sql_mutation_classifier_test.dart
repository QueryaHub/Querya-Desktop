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

  group('containsMutatingSql backslash escapes', () {
    const sql = r"SELECT 'a\'; DELETE FROM t; --'";

    test('the dialect decides whether the DELETE is code or part of a literal',
        () {
      expect(containsMutatingSql(sql), isFalse); // MySQL reading, the default
      expect(containsMutatingSql(sql, backslashEscapes: false), isTrue);
    });
  });

  group('readOnlyRefusal (#1773)', () {
    test('refuses writes and every way back to read-write', () {
      for (final sql in [
        'INSERT INTO t VALUES (1)',
        'DROP TABLE t',
        'BEGIN READ WRITE',
        'START TRANSACTION READ WRITE',
        'SET TRANSACTION READ WRITE',
        'SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE',
        'SET default_transaction_read_only = off',
        'SET SESSION transaction_read_only = off',
        'SET SESSION TRANSACTION READ WRITE',
        'SET GLOBAL read_only = 0',
        "SELECT set_config('default_transaction_read_only', 'off', false)",
        'EXPLAIN ANALYZE DELETE FROM t',
        'EXPLAIN (ANALYZE, VERBOSE) UPDATE t SET a = 1',
        'WITH d AS (DELETE FROM t RETURNING *) SELECT * FROM d',
        'CALL do_things()',
        "DO \$\$ BEGIN DELETE FROM t; END \$\$",
        "COPY t TO '/tmp/x'",
        'VACUUM t',
      ]) {
        expect(readOnlyRefusal(sql), isNotNull, reason: sql);
      }
    });

    test('lets reading and harmless settings through', () {
      for (final sql in [
        'SELECT * FROM t',
        'SELECT read_only FROM flags',
        "SHOW VARIABLES LIKE 'read_only'",
        'SET search_path TO public',
        'SET TRANSACTION READ ONLY',
        'BEGIN READ ONLY',
        'BEGIN',
        'EXPLAIN SELECT 1',
        'EXPLAIN DELETE FROM t',
        'EXPLAIN ANALYZE SELECT 1',
        "SELECT 'BEGIN READ WRITE' AS s",
        '-- BEGIN READ WRITE\nSELECT 1',
      ]) {
        expect(readOnlyRefusal(sql), isNull, reason: sql);
      }
    });

    test('a script is refused when any statement is', () {
      expect(readOnlyScriptRefusal('SELECT 1; SET default_transaction_read_only = off; DELETE FROM t'),
          isNotNull);
      expect(readOnlyScriptRefusal('SELECT 1; SELECT 2'), isNull);
    });
  });
}
