/// One statement of a script, as offsets into the script.
class SqlStatementSpan {
  const SqlStatementSpan({
    required this.start,
    required this.end,
    required this.line,
  });

  /// Offset of the first character of the statement (leading blanks skipped).
  final int start;

  /// Offset after its last character (trailing blanks and the `;` excluded).
  final int end;

  /// 1-based line of [start].
  final int line;

  String textIn(String sql) => sql.substring(start, end);
}

/// Splits SQL scripts into statement ranges. Semicolons inside string
/// literals, quoted identifiers, comments and PostgreSQL dollar quotes do not
/// end a statement.
abstract final class SqlStatementSplitter {
  /// `$tag$` or `$$`, matched at an offset (no `^`: it would only match at the
  /// start of the script). One compiled instance for every dollar sign.
  static final RegExp _dollarTag = RegExp(r'\$([a-zA-Z0-9_]*)\$');

  static List<SqlStatementSpan> spans(String sql) {
    final out = <SqlStatementSpan>[];
    final len = sql.length;
    var i = 0;
    var segmentStart = 0;

    // Statement starts only move forward, so the line of each one is found by
    // counting newlines from the previous start instead of from the top of the
    // script: one pass in total (#1350).
    var lineCountedTo = 0;
    var line = 1;
    int lineAt(int offset) {
      while (lineCountedTo < offset) {
        if (sql.codeUnitAt(lineCountedTo) == 0x0A) line++;
        lineCountedTo++;
      }
      return line;
    }

    void close(int end) {
      var s = segmentStart;
      var e = end;
      while (s < e && _isBlank(sql.codeUnitAt(s))) {
        s++;
      }
      while (e > s && _isBlank(sql.codeUnitAt(e - 1))) {
        e--;
      }
      if (e > s) {
        out.add(SqlStatementSpan(start: s, end: e, line: lineAt(s)));
      }
    }

    while (i < len) {
      final c = sql[i];

      // Line comment: runs to the end of the line.
      if (c == '-' && i + 1 < len && sql[i + 1] == '-') {
        while (i < len && sql[i] != '\n' && sql[i] != '\r') {
          i++;
        }
        continue;
      }

      // Block comment.
      if (c == '/' && i + 1 < len && sql[i + 1] == '*') {
        i += 2;
        while (i + 1 < len && !(sql[i] == '*' && sql[i + 1] == '/')) {
          i++;
        }
        i = i + 1 < len ? i + 2 : len;
        continue;
      }

      // Dollar quote: $tag$ ... $tag$.
      if (c == '\$') {
        final match = _dollarTag.matchAsPrefix(sql, i);
        if (match != null) {
          final tag = match.group(0)!;
          final close = sql.indexOf(tag, i + tag.length);
          i = close == -1 ? len : close + tag.length;
          continue;
        }
      }

      // String literal, with doubled quotes and backslash escapes.
      if (c == "'") {
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
        continue;
      }

      // Quoted identifier: "name" (PostgreSQL) or `name` (MySQL).
      if (c == '"' || c == '`') {
        i++;
        while (i < len) {
          if (sql[i] == c) {
            if (i + 1 < len && sql[i + 1] == c) {
              i += 2;
            } else {
              i++;
              break;
            }
          } else {
            i++;
          }
        }
        continue;
      }

      if (c == ';') {
        close(i);
        i++;
        segmentStart = i;
        continue;
      }

      i++;
    }
    close(len);
    return out;
  }

  /// The statement the caret at [offset] belongs to. Between statements (a
  /// blank line, or after the last `;`) it is the statement above; before the
  /// first statement it is the first one. Null for an empty script.
  static SqlStatementSpan? at(List<SqlStatementSpan> spans, int offset) {
    if (spans.isEmpty) return null;
    for (final s in spans) {
      if (offset >= s.start && offset <= s.end) return s;
    }
    SqlStatementSpan? above;
    for (final s in spans) {
      if (s.end <= offset) above = s;
    }
    return above ?? spans.first;
  }

  static bool _isBlank(int c) =>
      c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x0B || c == 0x0C;
}
