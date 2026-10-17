import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_lexical_scanner.dart';

List<(SqlSegmentKind, String)> _scan(String sql) => [
      for (final s in SqlLexicalScanner.segments(sql))
        (s.kind, sql.substring(s.start, s.end)),
    ];

void main() {
  group('SqlLexicalScanner', () {
    test('empty script has no segments', () {
      expect(SqlLexicalScanner.segments(''), isEmpty);
    });

    test('plain code is one segment', () {
      expect(_scan('select 1 from t'), [(SqlSegmentKind.code, 'select 1 from t')]);
    });

    test('splits literals, identifiers, comments and dollar quotes', () {
      expect(
        _scan("select 'a''b', \"c\", `d` -- e\nfrom t /* f */ where \$\$ g \$\$"),
        [
          (SqlSegmentKind.code, 'select '),
          (SqlSegmentKind.string, "'a''b'"),
          (SqlSegmentKind.code, ', '),
          (SqlSegmentKind.quotedIdentifier, '"c"'),
          (SqlSegmentKind.code, ', '),
          (SqlSegmentKind.quotedIdentifier, '`d`'),
          (SqlSegmentKind.code, ' '),
          (SqlSegmentKind.comment, '-- e'),
          (SqlSegmentKind.code, '\nfrom t '),
          (SqlSegmentKind.comment, '/* f */'),
          (SqlSegmentKind.code, ' where '),
          (SqlSegmentKind.dollarQuoted, r'$$ g $$'),
        ],
      );
    });

    test('a tagged dollar quote ends only at the same tag', () {
      expect(
        _scan(r'$fn$ a $$ b $fn$;'),
        [
          (SqlSegmentKind.dollarQuoted, r'$fn$ a $$ b $fn$'),
          (SqlSegmentKind.code, ';'),
        ],
      );
    });

    test(r'$1 placeholders stay code', () {
      expect(_scan(r'select $1, $2'), [(SqlSegmentKind.code, r'select $1, $2')]);
    });

    test('unterminated segments run to the end', () {
      expect(_scan("a 'b"), [
        (SqlSegmentKind.code, 'a '),
        (SqlSegmentKind.string, "'b"),
      ]);
      expect(_scan('a /* b'), [
        (SqlSegmentKind.code, 'a '),
        (SqlSegmentKind.comment, '/* b'),
      ]);
      expect(_scan('a "b'), [
        (SqlSegmentKind.code, 'a '),
        (SqlSegmentKind.quotedIdentifier, '"b'),
      ]);
    });

    test('segments cover the script without gaps', () {
      const sql = "x 'y' \"z\" -- w\n/* v */ \$t\$ u \$t\$ end";
      var at = 0;
      for (final s in SqlLexicalScanner.segments(sql)) {
        expect(s.start, at);
        expect(s.end, greaterThan(s.start));
        at = s.end;
      }
      expect(at, sql.length);
    });
  });
}
