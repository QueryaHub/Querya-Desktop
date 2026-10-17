import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/sql_script_format.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart'
    show SqlDialect;

void main() {
  test('uppercases SQL keywords and leaves identifiers', () {
    expect(
      formatSqlScript('select id from users where name = \'Ada\''),
      "SELECT id FROM users WHERE name = 'Ada'",
    );
  });

  group('leaves what is not code as written (#1566)', () {
    test('string literals', () {
      expect(
        formatSqlScript("select * from t where status = 'not null'"),
        "SELECT * FROM t WHERE status = 'not null'",
      );
    });

    test("doubled quotes and backslash escapes inside a literal", () {
      expect(
        formatSqlScript(r"select 'it''s in order', 'a\' or b' from t"),
        r"SELECT 'it''s in order', 'a\' or b' FROM t",
      );
    });

    test('quoted identifiers, PostgreSQL and MySQL', () {
      expect(
        formatSqlScript('select "order", "desc" from t'),
        'SELECT "order", "desc" FROM t',
      );
      expect(
        formatSqlScript('select `limit` from t'),
        'SELECT `limit` FROM t',
      );
    });

    test('dollar-quoted function bodies', () {
      const body = r'$$ begin update t set x = 1; end $$';
      expect(
        formatSqlScript('create function f() returns void as $body language sql'),
        'CREATE function f() returns void AS $body language sql',
      );
      expect(
        formatSqlScript(r'do $fn$ begin null; end $fn$'),
        r'do $fn$ begin null; end $fn$',
      );
    });

    test('line and block comments', () {
      expect(
        formatSqlScript('-- set in prod\nselect 1 /* and not here */ from t'),
        '-- set in prod\nSELECT 1 /* and not here */ FROM t',
      );
    });

    test('an unterminated literal runs to the end', () {
      expect(
        formatSqlScript("select 'from where"),
        "SELECT 'from where",
      );
    });
  });

  test('keeps the length of the script', () {
    const sql = "select a, \"b\" from t -- x\nwhere c = 'and' and d is null";
    expect(formatSqlScript(sql).length, sql.length);
  });

  group('backslashes follow the dialect', () {
    test(r"PostgreSQL: a literal ending in \ does not swallow the next one", () {
      expect(
        formatSqlScript(r"select 'C:\', 'not null' from t",
            dialect: SqlDialect.postgres),
        r"SELECT 'C:\', 'not null' FROM t",
      );
    });

    test('SQLite: the same', () {
      expect(
        formatSqlScript(r"select 'C:\' as p where x = 'and'",
            dialect: SqlDialect.sqlite),
        r"SELECT 'C:\' AS p WHERE x = 'and'",
      );
    });

    test(r"MySQL: \' is an escaped quote inside the literal", () {
      expect(
        formatSqlScript(r"select 'it\'s or not' from t",
            dialect: SqlDialect.mysql),
        r"SELECT 'it\'s or not' FROM t",
      );
    });
  });
}
