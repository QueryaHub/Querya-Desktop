import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/sql_lexical_scanner.dart';

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
  static const int _chSemicolon = 0x3B;
  static const int _chLf = 0x0A;

  /// Default script size threshold (64 KB) above which [spansAsync] offloads
  /// parsing to a background isolate via [compute].
  static const int defaultIsolateThreshold = 64 * 1024;

  /// Splits [sql] into statement ranges asynchronously. If [sql.length] exceeds
  /// [isolateThreshold], parsing runs in a background isolate via [compute] so
  /// large scripts do not block the UI thread (#1350).
  static Future<List<SqlStatementSpan>> spansAsync(
    String sql, {
    int isolateThreshold = defaultIsolateThreshold,
    bool backslashEscapes = true,
  }) async {
    if (sql.length <= isolateThreshold) {
      return spans(sql, backslashEscapes: backslashEscapes);
    }
    return compute(_spansInIsolate, (sql, backslashEscapes));
  }

  static List<SqlStatementSpan> _spansInIsolate((String, bool) args) =>
      spans(args.$1, backslashEscapes: args.$2);

  /// [backslashEscapes] says whether `\'` escapes a quote inside `'...'`, as
  /// it does in MySQL (the default, and what an unknown dialect gets). Pass
  /// `dialect.backslashEscapesQuotes` when the dialect is known: reading
  /// `'a\'` as an unfinished literal in PostgreSQL or SQLite hides the `;`
  /// after it, and the statement the server then runs.
  static List<SqlStatementSpan> spans(
    String sql, {
    bool backslashEscapes = true,
  }) {
    final out = <SqlStatementSpan>[];
    final len = sql.length;
    var segmentStart = 0;

    // Statement starts only move forward, so the line of each one is found by
    // counting newlines from the previous start instead of from the top of the
    // script: one pass in total (#1350).
    var lineCountedTo = 0;
    var line = 1;
    int lineAt(int offset) {
      while (lineCountedTo < offset) {
        if (sql.codeUnitAt(lineCountedTo) == _chLf) line++;
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

    // A `;` ends a statement only in code: literals, quoted identifiers,
    // comments and dollar quotes are the scanner's other segments.
    for (final segment in SqlLexicalScanner.segments(
      sql,
      backslashEscapes: backslashEscapes,
    )) {
      if (segment.kind != SqlSegmentKind.code) continue;
      for (var i = segment.start; i < segment.end; i++) {
        if (sql.codeUnitAt(i) == _chSemicolon) {
          close(i);
          segmentStart = i + 1;
        }
      }
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
