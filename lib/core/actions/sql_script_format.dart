import 'package:querya_desktop/core/database/sql_lexical_scanner.dart';

const _kSqlKeywords = {
  'ADD',
  'ALL',
  'ALTER',
  'AND',
  'AS',
  'ASC',
  'BEGIN',
  'BETWEEN',
  'BY',
  'CASE',
  'CAST',
  'COMMIT',
  'CREATE',
  'CROSS',
  'DELETE',
  'DESC',
  'DISTINCT',
  'DROP',
  'ELSE',
  'END',
  'EXCEPT',
  'EXISTS',
  'FROM',
  'FULL',
  'GROUP',
  'HAVING',
  'IN',
  'INNER',
  'INSERT',
  'INTERSECT',
  'INTO',
  'IS',
  'JOIN',
  'LEFT',
  'LIKE',
  'LIMIT',
  'NOT',
  'NULL',
  'OFFSET',
  'ON',
  'OR',
  'ORDER',
  'OUTER',
  'RETURNING',
  'RIGHT',
  'ROLLBACK',
  'SELECT',
  'SET',
  'TABLE',
  'THEN',
  'UNION',
  'UPDATE',
  'USING',
  'VALUES',
  'WHEN',
  'WHERE',
  'WITH',
};

final _kSqlWord = RegExp(r"[A-Za-z_][A-Za-z0-9_]*");

/// Uppercases SQL keywords. Enough for palette "Format SQL" without a parser.
///
/// Only code is touched: string literals, quoted identifiers, comments and
/// dollar-quoted bodies are kept as written (#1566). Keywords keep their
/// length, so every offset into [sql] is the same offset into the result.
String formatSqlScript(String sql) {
  final out = StringBuffer();
  for (final segment in SqlLexicalScanner.segments(sql)) {
    final text = sql.substring(segment.start, segment.end);
    if (segment.kind != SqlSegmentKind.code) {
      out.write(text);
      continue;
    }
    out.write(text.replaceAllMapped(_kSqlWord, (match) {
      final word = match[0]!;
      final upper = word.toUpperCase();
      return _kSqlKeywords.contains(upper) ? upper : word;
    }));
  }
  return out.toString();
}
