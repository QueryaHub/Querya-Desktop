/// What a stretch of SQL text is, lexically.
enum SqlSegmentKind {
  /// Keywords, identifiers, operators, numbers and blanks.
  code,

  /// `'...'`, with `''` and backslash escapes.
  string,

  /// `"name"` (PostgreSQL, standard SQL) or `` `name` `` (MySQL).
  quotedIdentifier,

  /// `-- ...` up to the line break, or `/* ... */`.
  comment,

  /// `$$ ... $$` or `$tag$ ... $tag$` (PostgreSQL function bodies).
  dollarQuoted,
}

/// One segment of a script, as offsets into the script.
class SqlSegment {
  const SqlSegment(this.kind, this.start, this.end);

  final SqlSegmentKind kind;

  /// Offset of the first character, including the opening quote or `--`.
  final int start;

  /// Offset after the last character, including the closing quote.
  final int end;

  @override
  bool operator ==(Object other) =>
      other is SqlSegment &&
      other.kind == kind &&
      other.start == start &&
      other.end == end;

  @override
  int get hashCode => Object.hash(kind, start, end);

  @override
  String toString() => 'SqlSegment(${kind.name}, $start, $end)';
}

/// Splits SQL into code and the parts that are not code (literals, quoted
/// identifiers, comments, dollar quotes), with the same rules as
/// `SqlStatementSplitter`. An unterminated literal or comment runs to the end.
abstract final class SqlLexicalScanner {
  static final RegExp _dollarTag = RegExp(r'\$([a-zA-Z0-9_]*)\$');

  static const int _chDash = 0x2D;
  static const int _chSlash = 0x2F;
  static const int _chAsterisk = 0x2A;
  static const int _chDollar = 0x24;
  static const int _chSingleQuote = 0x27;
  static const int _chDoubleQuote = 0x22;
  static const int _chBacktick = 0x60;
  static const int _chBackslash = 0x5C;
  static const int _chLf = 0x0A;
  static const int _chCr = 0x0D;

  /// Segments that cover [sql] end to end, in order; neighbouring code is
  /// one segment.
  static List<SqlSegment> segments(String sql) {
    final out = <SqlSegment>[];
    final len = sql.length;
    var codeStart = 0;
    var i = 0;

    void add(SqlSegmentKind kind, int start, int end) {
      if (start > codeStart) {
        out.add(SqlSegment(SqlSegmentKind.code, codeStart, start));
      }
      out.add(SqlSegment(kind, start, end));
      codeStart = end;
    }

    while (i < len) {
      final code = sql.codeUnitAt(i);

      if (code == _chDash && i + 1 < len && sql.codeUnitAt(i + 1) == _chDash) {
        var j = i + 2;
        while (j < len &&
            sql.codeUnitAt(j) != _chLf &&
            sql.codeUnitAt(j) != _chCr) {
          j++;
        }
        add(SqlSegmentKind.comment, i, j);
        i = j;
        continue;
      }

      if (code == _chSlash &&
          i + 1 < len &&
          sql.codeUnitAt(i + 1) == _chAsterisk) {
        final close = sql.indexOf('*/', i + 2);
        final end = close == -1 ? len : close + 2;
        add(SqlSegmentKind.comment, i, end);
        i = end;
        continue;
      }

      if (code == _chDollar) {
        final match = _dollarTag.matchAsPrefix(sql, i);
        if (match != null) {
          final tag = match.group(0)!;
          final close = sql.indexOf(tag, i + tag.length);
          final end = close == -1 ? len : close + tag.length;
          add(SqlSegmentKind.dollarQuoted, i, end);
          i = end;
          continue;
        }
      }

      if (code == _chSingleQuote) {
        var j = i + 1;
        while (j < len) {
          final curr = sql.codeUnitAt(j);
          if (curr == _chSingleQuote) {
            if (j + 1 < len && sql.codeUnitAt(j + 1) == _chSingleQuote) {
              j += 2;
            } else {
              j++;
              break;
            }
          } else if (curr == _chBackslash && j + 1 < len) {
            j += 2;
          } else {
            j++;
          }
        }
        add(SqlSegmentKind.string, i, j);
        i = j;
        continue;
      }

      if (code == _chDoubleQuote || code == _chBacktick) {
        var j = i + 1;
        while (j < len) {
          if (sql.codeUnitAt(j) == code) {
            if (j + 1 < len && sql.codeUnitAt(j + 1) == code) {
              j += 2;
            } else {
              j++;
              break;
            }
          } else {
            j++;
          }
        }
        add(SqlSegmentKind.quotedIdentifier, i, j);
        i = j;
        continue;
      }

      i++;
    }
    if (len > codeStart) {
      out.add(SqlSegment(SqlSegmentKind.code, codeStart, len));
    }
    return out;
  }
}
