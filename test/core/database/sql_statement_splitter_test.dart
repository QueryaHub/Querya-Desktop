import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/sql_statement_splitter.dart';

List<String> texts(String sql) => [
      for (final s in SqlStatementSplitter.spans(sql)) s.textIn(sql),
    ];

void main() {
  group('SqlStatementSplitter.spans', () {
    test('splits on semicolons and skips empty statements', () {
      expect(texts('select 1;;  select 2 ;\n'), ['select 1', 'select 2']);
    });

    test('a semicolon inside quotes or comments does not end a statement', () {
      expect(texts("select 'a;b'; select \"c;d\"; -- x; y\nselect 3"), [
        "select 'a;b'",
        'select "c;d"',
        '-- x; y\nselect 3',
      ]);
      expect(texts('select 1 /* ; */; select 2'), [
        'select 1 /* ; */',
        'select 2',
      ]);
    });

    test("doubled quotes and backslash escapes stay inside a literal", () {
      expect(texts("select 'it''s;'; select 'x\\';y'"), [
        "select 'it''s;'",
        "select 'x\\';y'",
      ]);
    });

    test('PostgreSQL dollar quoting keeps its semicolons', () {
      expect(
        texts('create function f() returns int as \$\$ select 1; \$\$ '
            'language sql; select 2'),
        [
          'create function f() returns int as \$\$ select 1; \$\$ '
              'language sql',
          'select 2',
        ],
      );
    });

    test('offsets and lines point at the statement text', () {
      const sql = 'select 1;\n\n  select 2';
      final spans = SqlStatementSplitter.spans(sql);
      expect(spans.length, 2);
      expect(spans[1].textIn(sql), 'select 2');
      expect(spans[1].line, 3);
      expect(spans[0].line, 1);
    });

    test('the destructive detector splits the same way', () {
      const sql = "select 'a;b'; drop table t; -- ;\n";
      expect(DestructiveSqlDetector.splitStatements(sql), texts(sql));
    });
  });

  group('SqlStatementSplitter.at', () {
    const sql = 'select 1;\nselect 2;\nselect 3';
    final spans = SqlStatementSplitter.spans(sql);

    test('the caret inside the second of three statements picks it', () {
      final offset = sql.indexOf('2') + 1;
      expect(SqlStatementSplitter.at(spans, offset)!.textIn(sql), 'select 2');
    });

    test('a caret on a blank line between statements takes the one above', () {
      const blank = 'select 1;\n\nselect 2';
      final b = SqlStatementSplitter.spans(blank);
      final offset = blank.indexOf('\n\n') + 1;
      expect(SqlStatementSplitter.at(b, offset)!.textIn(blank), 'select 1');
    });

    test('a caret after the last semicolon takes the last statement', () {
      const trailing = 'select 1; select 2;';
      final t = SqlStatementSplitter.spans(trailing);
      expect(SqlStatementSplitter.at(t, trailing.length)!.textIn(trailing),
          'select 2');
    });

    test('a caret before the first statement takes the first one', () {
      const leading = '   select 1';
      final l = SqlStatementSplitter.spans(leading);
      expect(SqlStatementSplitter.at(l, 0)!.textIn(leading), 'select 1');
    });

    test('an empty script has no statement', () {
      expect(SqlStatementSplitter.at(SqlStatementSplitter.spans('  ;  '), 0),
          isNull);
    });
  });
}
