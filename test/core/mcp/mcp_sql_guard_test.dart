import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_guard.dart';

void main() {
  void allowed(String sql, [SqlDialect d = SqlDialect.postgres]) =>
      expect(McpSqlGuard.check(sql, d), isNull, reason: sql);
  void refused(String sql, [SqlDialect d = SqlDialect.postgres]) =>
      expect(McpSqlGuard.check(sql, d), isNotNull, reason: sql);

  test('read-only statements are allowed', () {
    allowed('SELECT 1');
    allowed('select * from users where id = 1;');
    allowed('  -- comment\n SELECT name FROM users');
    allowed('(SELECT 1) UNION (SELECT 2)');
    allowed('WITH t AS (SELECT 1 AS n) SELECT n FROM t');
    allowed('EXPLAIN SELECT * FROM users');
    allowed('EXPLAIN (FORMAT JSON) SELECT 1');
    allowed('SHOW search_path');
    allowed('DESCRIBE users', SqlDialect.mysql);
    allowed('VALUES (1), (2)');
    allowed("SELECT 'DROP TABLE users; DELETE FROM x' AS text");
    allowed('SELECT 1 /* UPDATE users SET a = 1 */');
  });

  test('writes and DDL are refused', () {
    for (final sql in [
      'INSERT INTO users VALUES (1)',
      'UPDATE users SET name = 1',
      'DELETE FROM users',
      'MERGE INTO t USING s ON true WHEN MATCHED THEN DELETE',
      'REPLACE INTO users VALUES (1)',
      'TRUNCATE users',
      'DROP TABLE users',
      'CREATE TABLE x (id int)',
      'ALTER TABLE users ADD c int',
      'GRANT ALL ON users TO bob',
      'COPY users TO \'/tmp/x\'',
      'CALL do_things()',
      'DO \$\$ BEGIN END \$\$',
      'SET ROLE admin',
      'BEGIN',
      'VACUUM',
      'ATTACH DATABASE \'/tmp/x.db\' AS x',
    ]) {
      refused(sql);
    }
  });

  test('data-modifying CTEs are refused', () {
    refused('WITH d AS (DELETE FROM users RETURNING *) SELECT * FROM d');
    refused('WITH u AS (UPDATE users SET a = 1 RETURNING id) SELECT 1');
  });

  test('more than one statement is refused', () {
    refused('SELECT 1; DROP TABLE users');
    refused('SELECT 1; SELECT 2');
  });

  test('empty input is refused', () {
    refused('');
    refused('  -- only a comment');
  });

  test('EXPLAIN ANALYZE and EXPLAIN of a write are refused', () {
    refused('EXPLAIN ANALYZE SELECT 1');
    refused('EXPLAIN (ANALYZE, BUFFERS) SELECT 1');
    refused('EXPLAIN DELETE FROM users');
    refused('EXPLAIN ANALYZE DELETE FROM users');
  });

  test('SELECT INTO, OUTFILE and row locks are refused', () {
    refused('SELECT * INTO backup FROM users');
    refused("SELECT * FROM users INTO OUTFILE '/tmp/u.csv'", SqlDialect.mysql);
    refused('SELECT * FROM users FOR UPDATE');
    refused('SELECT * FROM users FOR SHARE');
    refused('SELECT * FROM users LOCK IN SHARE MODE', SqlDialect.mysql);
  });

  test('server-side functions with effects are refused', () {
    refused('SELECT pg_terminate_backend(123)');
    refused('SELECT pg_read_file(\'/etc/passwd\')');
    refused('SELECT * FROM dblink(\'x\', \'DELETE FROM y\') AS t(a int)');
    refused("SELECT set_config('default_transaction_read_only', 'off', false)");
    refused("SELECT LOAD_FILE('/etc/passwd')", SqlDialect.mysql);
    refused("SELECT load_extension('evil')", SqlDialect.sqlite);
  });

  test('SQLite schema pragmas are allowed, others are refused', () {
    allowed('PRAGMA table_info(users)', SqlDialect.sqlite);
    allowed('PRAGMA index_list(users)', SqlDialect.sqlite);
    allowed('PRAGMA foreign_key_list(users)', SqlDialect.sqlite);
    allowed('PRAGMA database_list', SqlDialect.sqlite);
    refused('PRAGMA query_only = OFF', SqlDialect.sqlite);
    refused('PRAGMA writable_schema = ON', SqlDialect.sqlite);
    refused('PRAGMA journal_mode', SqlDialect.sqlite);
    refused('PRAGMA table_info(users)', SqlDialect.postgres);
  });

  group('refusal rule ids (#1231)', () {
    String? ruleOf(String sql, SqlDialect d) =>
        McpSqlGuard.refusal(sql, d)?.rule;

    test('every refusal names the rule that caught it', () {
      expect(ruleOf('', SqlDialect.postgres), 'empty_query');
      expect(ruleOf('SELECT 1; SELECT 2', SqlDialect.postgres),
          'single_statement');
      expect(ruleOf('INSERT INTO t VALUES (1)', SqlDialect.sqlite),
          'read_only_only');
      expect(ruleOf('PRAGMA writable_schema = 1', SqlDialect.sqlite),
          'sqlite_pragma');
      expect(ruleOf('/*! DROP TABLE t */ SELECT 1', SqlDialect.mysql),
          'mysql_executable_comment');
      expect(ruleOf('WITH x AS (SELECT 1) DELETE FROM t', SqlDialect.postgres),
          'data_modifying');
      expect(ruleOf('SELECT 1 FOR UPDATE', SqlDialect.postgres),
          'select_into_or_lock');
      expect(ruleOf('EXPLAIN ANALYZE SELECT 1', SqlDialect.postgres),
          'explain_analyze_or_write');
    });

    test('a query that may run has no refusal and no rule', () {
      expect(McpSqlGuard.refusal('SELECT 1', SqlDialect.postgres), isNull);
      expect(McpSqlGuard.check('SELECT 1', SqlDialect.postgres), isNull);
    });

    test('the message the model reads is unchanged by the rule id', () {
      expect(McpSqlGuard.check('', SqlDialect.postgres),
          'The query is empty.');
      expect(McpSqlGuard.refusal('', SqlDialect.postgres)!.message,
          'The query is empty.');
    });
  });
}
