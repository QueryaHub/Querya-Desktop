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

final _limitAll = RegExp(r'\bLIMIT\s+ALL\b', caseSensitive: false);
final _limitCount = RegExp(
  r'\bLIMIT\s+(\d+)(\s+OFFSET\s+\d+)?',
  caseSensitive: false,
);
final _fetchFirst = RegExp(
  r'\bFETCH\s+(?:FIRST|NEXT)\s+(\d+)\s+ROWS?\s+ONLY\b',
  caseSensitive: false,
);

/// Injects or clamps a `LIMIT` on read-only queries (`SELECT`, `WITH`, `VALUES`).
///
/// - No `LIMIT` / `FETCH … ONLY` → appends `LIMIT [limit]`.
/// - `LIMIT ALL` → replaced with `LIMIT [limit]`.
/// - `LIMIT n [OFFSET m]` where `n > limit` → clamped to [limit].
/// - `FETCH FIRST/NEXT n ROWS ONLY` where `n > limit` → clamped.
/// - Non-select statements are returned unchanged.
///
/// Trailing semicolons are preserved after an injected clause.
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

  if (_limitAll.hasMatch(sql)) {
    return sql.replaceFirst(_limitAll, 'LIMIT $limit');
  }

  final limitMatch = _limitCount.firstMatch(sql);
  if (limitMatch != null) {
    final existing = int.tryParse(limitMatch.group(1)!);
    if (existing == null || existing <= limit) {
      return sql;
    }
    final offsetPart = limitMatch.group(2) ?? '';
    return sql.replaceFirst(
      limitMatch.group(0)!,
      'LIMIT $limit$offsetPart',
    );
  }

  final fetchMatch = _fetchFirst.firstMatch(sql);
  if (fetchMatch != null) {
    final existing = int.tryParse(fetchMatch.group(1)!);
    if (existing == null || existing <= limit) {
      return sql;
    }
    return sql.replaceFirst(
      fetchMatch.group(0)!,
      'FETCH FIRST $limit ROWS ONLY',
    );
  }

  if (RegExp(r'\bLIMIT\b', caseSensitive: false).hasMatch(sql) ||
      RegExp(r'\bFETCH\b', caseSensitive: false).hasMatch(sql)) {
    // Unrecognized LIMIT/FETCH shape — leave unchanged.
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
