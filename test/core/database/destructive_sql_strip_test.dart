import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';

/// `stripCommentsAndStrings` as it was before #1511 (regex + substring at each
/// `$`, one-character strings), kept as the reference the scanner must match.
String _reference(String sql) {
  final buffer = StringBuffer();
  final len = sql.length;
  var i = 0;

  while (i < len) {
    if (i + 1 < len && sql[i] == '-' && sql[i + 1] == '-') {
      i += 2;
      while (i < len && sql[i] != '\n' && sql[i] != '\r') {
        i++;
      }
      buffer.write(' ');
      continue;
    }
    if (i + 1 < len && sql[i] == '/' && sql[i + 1] == '*') {
      i += 2;
      while (i + 1 < len && !(sql[i] == '*' && sql[i + 1] == '/')) {
        i++;
      }
      if (i + 1 < len) {
        i += 2;
      } else {
        i = len;
      }
      buffer.write(' ');
      continue;
    }
    if (sql[i] == '\$') {
      final match =
          RegExp(r'^\$([a-zA-Z0-9_]*)\$').matchAsPrefix(sql.substring(i));
      if (match != null) {
        final tag = match.group(0)!;
        i += tag.length;
        final closeIdx = sql.indexOf(tag, i);
        if (closeIdx != -1) {
          i = closeIdx + tag.length;
        } else {
          i = len;
        }
        buffer.write("''");
        continue;
      }
    }
    if (sql[i] == "'") {
      i++;
      while (i < len) {
        if (sql[i] == "'") {
          if (i + 1 < len && sql[i + 1] == "'") {
            i += 2;
          } else {
            i++;
            break;
          }
        } else if (sql[i] == '\\' && i + 1 < len) {
          i += 2;
        } else {
          i++;
        }
      }
      buffer.write("''");
      continue;
    }
    buffer.write(sql[i]);
    i++;
  }
  return buffer.toString();
}

void main() {
  group('stripCommentsAndStrings scanner (#1511)', () {
    test('matches the previous implementation on hand-written scripts', () {
      const cases = <String>[
        '',
        'SELECT 1',
        '-- only a comment',
        'SELECT 1 -- tail\nFROM t',
        'SELECT 1 -- tail\r\nFROM t',
        '/* block */ SELECT 1',
        'SELECT /* unterminated',
        'SELECT /* a */ 1 /* b */',
        '/**/SELECT/***/1',
        "SELECT 'it''s' FROM t",
        "SELECT 'a\\'b' FROM t",
        "SELECT 'unterminated",
        "SELECT 'x\\",
        r'SELECT $$ DROP TABLE x; $$ FROM t',
        r'SELECT $fn$ body $fn$ , $1, $2',
        r'SELECT $a$ never closed',
        r'SELECT $ alone, $1, $_x$ one $_x$',
        r'SELECT $$$$',
        r"DO $$ BEGIN RAISE NOTICE 'x'; END $$;",
        "DELETE FROM t WHERE a = 'WHERE' -- WHERE\n",
        '-',
        '/',
        '\$',
        "'",
        'aé\u{1F600}b -- \u{1F600}\n\'\u{1F600}\'',
      ];
      for (final sql in cases) {
        expect(
          DestructiveSqlDetector.stripCommentsAndStrings(sql),
          _reference(sql),
          reason: sql,
        );
      }
    });

    test('matches the previous implementation on random SQL-like text', () {
      const pieces = <String>[
        "'", "''", '"', '--', '/*', '*/', '\n', '\r\n', ' ', ';', r'$', r'$$',
        r'$a$', r'$tag$', r'$1', r'\', 'SELECT', 'DROP', 'WHERE', 'x', '1',
        '(', ')', 'é', '\u{1F600}', '-', '/', '*',
      ];
      final random = Random(1511);
      for (var n = 0; n < 3000; n++) {
        final sql = [
          for (var k = random.nextInt(30); k > 0; k--)
            pieces[random.nextInt(pieces.length)],
        ].join();
        expect(
          DestructiveSqlDetector.stripCommentsAndStrings(sql),
          _reference(sql),
          reason: sql,
        );
      }
    });

    test('a large script with many parameters is handled', () {
      final sql = List.generate(20000, (i) => 'SELECT \$1, \$2 -- row $i')
          .join('\n');
      final out = DestructiveSqlDetector.stripCommentsAndStrings(sql);
      expect(out, _reference(sql));
      expect(out, isNot(contains('row')));
    });
  });
}
