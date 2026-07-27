// Shared helpers for bounding ad-hoc SQL result sets (Postgres, SQLite, …).

/// Removes leading whitespace and `--` line comments (not `/* */`).
String stripLeadingWhitespaceAndLineComments(String sql) {
  var s = sql.trimLeft();
  while (true) {
    if (s.isEmpty) return s;
    if (s.startsWith('--')) {
      final nl = s.indexOf('\n');
      if (nl == -1) return '';
      s = s.substring(nl + 1).trimLeft();
      continue;
    }
    return s;
  }
}

/// Injects a `LIMIT` clause into a read-only query (`SELECT`, `WITH`, `VALUES`)
/// when it does not already contain `LIMIT`.
///
/// Existing `LIMIT` is left unchanged (caller may still apply a client-side
/// display cap). Non-select statements are returned as-is.
///
/// Trailing semicolons are preserved after the injected clause.
String injectSqlLimit(String sql, int limit) {
  if (limit <= 0) return sql;

  final cleanSql = stripLeadingWhitespaceAndLineComments(sql);
  final upper = cleanSql.toUpperCase();

  final isSelect = upper.startsWith('SELECT') ||
      upper.startsWith('WITH') ||
      upper.startsWith('VALUES');

  if (!isSelect) {
    return sql;
  }

  // Already bounded by the author (may still exceed UI cap — see clamp issue).
  final hasLimit = RegExp(r'\bLIMIT\b', caseSensitive: false).hasMatch(sql);
  if (hasLimit) {
    return sql;
  }

  var body = sql.trimRight();
  var suffix = '';

  while (true) {
    if (body.isEmpty) break;
    if (body.endsWith(';')) {
      body = body.substring(0, body.length - 1).trimRight();
      suffix = ';$suffix';
      continue;
    }
    break;
  }

  return '$body\nLIMIT $limit$suffix';
}
