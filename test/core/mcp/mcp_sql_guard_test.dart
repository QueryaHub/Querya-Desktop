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

  test('functions with side effects beyond the transaction are refused (#1565)',
      () {
    refused("SELECT query_to_xml('DELETE FROM y', true, true, '')");
    refused("SELECT cursor_to_xml('c', 1, true, true, '')");
    refused("SELECT table_to_xml('t', true, true, '')");
    refused('SELECT pg_advisory_lock(1)');
    refused('SELECT pg_try_advisory_xact_lock(1)');
    refused('SELECT pg_sleep(60)');
    refused("SELECT lo_get(1234)");
    refused("SELECT nextval('s')");
    refused("SELECT setval('s', 10)");
  });

  test('a denylisted function is refused quoted, qualified and spaced (#1769)',
      () {
    refused('SELECT pg_catalog."pg_terminate_backend"(123)');
    refused('''SELECT "nextval"('s')''');
    refused('SELECT "pg_sleep" (60)');
    refused('SELECT pg_catalog.pg_sleep (60)');
    refused('SELECT pg_sleep /* c */ (60)');
    refused('SELECT pg_stat_reset()');
    refused("SELECT pg_create_restore_point('x')");
    refused('SELECT pg_promote()');
    refused('SELECT SLEEP(5)', SqlDialect.mysql);
    refused("SELECT BENCHMARK(1000000, MD5('a'))", SqlDialect.mysql);
    refused("SELECT GET_LOCK('l', 10)", SqlDialect.mysql);
    refused("SELECT RELEASE_LOCK('l')", SqlDialect.mysql);
    refused("SELECT IS_FREE_LOCK('l')", SqlDialect.mysql);
    refused('SELECT `sleep`(5)', SqlDialect.mysql);
  });

  test('syntax the stripper and the server read differently is refused', () {
    refused('''SELECT 1 AS "--", pg_sleep(100)''');
    refused('''SELECT 1 AS "'", pg_read_file('/etc/passwd') AS "'"''');
    refused(r'SELECT U&"pg_sl\0065ep"(5)');
    refused('SELECT 1 AS `--`, SLEEP(10)', SqlDialect.mysql);
    refused('SELECT 1--1, SLEEP(30)', SqlDialect.mysql);
    refused("SELECT 1 # '\n, SLEEP(10) # '", SqlDialect.mysql);
  });

  test('ordinary quoting is still allowed', () {
    allowed('''SELECT "id" FROM users WHERE name = 'x' AND "age" > 3''');
    allowed('''SELECT "a", "b" FROM t WHERE c = 'it''s' ''');
    allowed("SELECT '#fff', 'a--b' FROM t", SqlDialect.mysql);
    allowed('SELECT 1 -- a note', SqlDialect.mysql);
  });

  test('more server-side functions are refused (review of #1769)', () {
    refused("SELECT pg_notify('chan', 'x')");
    refused('SELECT * FROM pg_ls_logdir()');
    refused('SELECT pg_stat_statements_reset()');
    refused("SELECT pg_create_logical_replication_slot('s', 'test_decoding')");
    refused("SELECT pg_logical_slot_get_changes('s', NULL, NULL)");
    refused("SELECT pg_replication_slot_advance('s', '0/0')");
  });

  test('EXPLAIN of a SELECT that calls REPLACE() is allowed (#1565)', () {
    allowed("EXPLAIN SELECT REPLACE(name, 'a', 'b') FROM users");
    refused("EXPLAIN REPLACE INTO users VALUES (1)", SqlDialect.mysql);
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
      expect(ruleOf('SELECT pg_terminate_backend(1)', SqlDialect.postgres),
          'function_not_allowed');
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

  // A backslash before the closing quote is an escape in MySQL only; reading it
  // as one in PostgreSQL or SQLite hid the statements after the literal.
  test('a trailing backslash in a literal does not hide statements (PostgreSQL, SQLite)',
      () {
    const smuggled = r"SELECT 'a\'; SELECT pg_terminate_backend(1); --'";
    refused(smuggled, SqlDialect.postgres);
    refused(smuggled, SqlDialect.sqlite);
    const write = r"SELECT 'a\'; DELETE FROM users; --'";
    refused(write, SqlDialect.postgres);
    refused(write, SqlDialect.sqlite);
    expect(McpSqlGuard.refusal(write, SqlDialect.postgres)!.rule, 'single_statement');
  });

  test('the same text is one literal in MySQL, and an E string in PostgreSQL',
      () {
    allowed(r"SELECT 'a\'; SELECT pg_terminate_backend(1); --'", SqlDialect.mysql);
    allowed(r"SELECT E'a\'; SELECT 1'", SqlDialect.postgres);
  });
}
