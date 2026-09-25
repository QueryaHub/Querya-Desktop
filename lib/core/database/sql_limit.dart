// Shared helpers for bounding ad-hoc SQL result sets (Postgres, SQLite, MySQL, …).

/// Index just past a `/* ... */` comment starting at [start] (nested comments
/// are balanced, as in PostgreSQL). Returns `sql.length` when unterminated.
int _blockCommentEnd(String sql, int start) {
  var depth = 0;
  var i = start;
  while (i < sql.length) {
    if (sql.startsWith('/*', i)) {
      depth++;
      i += 2;
    } else if (sql.startsWith('*/', i)) {
      depth--;
      i += 2;
      if (depth == 0) return i;
    } else {
      i++;
    }
  }
  return sql.length;
}

/// Removes leading whitespace, `--` line comments and `/* */` block comments.
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
    if (s.startsWith('/*')) {
      s = s.substring(_blockCommentEnd(s, 0)).trimLeft();
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

/// Masks SQL comments and (unless [keepLiterals]) string / identifier /
/// dollar-quoted literals with spaces so keyword regexes do not match inside
/// them (same length, same offsets). Newlines inside comments are kept.
String maskSqlLiteralsForLimitScan(String sql, {bool keepLiterals = false}) {
  final out = StringBuffer();

  void blank(int from, int to) {
    for (var k = from; k < to; k++) {
      out.write(sql[k] == '\n' ? '\n' : ' ');
    }
  }

  void literal(int from, int to) {
    if (keepLiterals) {
      out.write(sql.substring(from, to));
    } else {
      out.write(' ' * (to - from));
    }
  }

  // Index just past a quoted run that starts at [start]; [q] escapes by doubling.
  int quotedEnd(int start, int q) {
    var i = start + 1;
    while (i < sql.length) {
      if (sql.codeUnitAt(i) == q) {
        if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == q) {
          i += 2;
          continue;
        }
        return i + 1;
      }
      i++;
    }
    return sql.length;
  }

  var i = 0;
  while (i < sql.length) {
    final c = sql.codeUnitAt(i);

    // Line comment: -- to end of line (the newline itself is kept).
    if (c == 0x2D /* - */ && sql.startsWith('--', i)) {
      var end = sql.indexOf('\n', i);
      if (end == -1) end = sql.length;
      blank(i, end);
      i = end;
      continue;
    }

    // Block comment: /* ... */ (nested).
    if (c == 0x2F /* / */ && sql.startsWith('/*', i)) {
      final end = _blockCommentEnd(sql, i);
      blank(i, end);
      i = end;
      continue;
    }

    // Single-quoted string or double-quoted identifier; doubled quote escapes.
    if (c == 0x27 /* ' */ || c == 0x22 /* " */) {
      final end = quotedEnd(i, c);
      literal(i, end);
      i = end;
      continue;
    }

    // Dollar-quoted string: $tag$ ... $tag$
    if (c == 0x24 /* $ */) {
      final tagEnd = sql.indexOf('\$', i + 1);
      if (tagEnd != -1) {
        final tag = sql.substring(i, tagEnd + 1);
        final close = sql.indexOf(tag, tagEnd + 1);
        if (close != -1) {
          final end = close + tag.length;
          literal(i, end);
          i = end;
          continue;
        }
      }
    }

    out.write(sql[i]);
    i++;
  }
  return out.toString();
}

/// Matches of [pattern] outside literals / comments and outside any
/// parentheses, so `LIMIT` / `FETCH` inside a CTE or subquery is ignored.
List<Match> _topLevelMatches(RegExp pattern, String sql) {
  final masked = maskSqlLiteralsForLimitScan(sql);
  final result = <Match>[];
  var depth = 0;
  var pos = 0;
  for (final m in pattern.allMatches(masked)) {
    for (; pos < m.start; pos++) {
      final ch = masked.codeUnitAt(pos);
      if (ch == 0x28 /* ( */) {
        depth++;
      } else if (ch == 0x29 /* ) */ && depth > 0) {
        depth--;
      }
    }
    if (depth == 0) result.add(m);
  }
  return result;
}

/// The last top-level match: the outer query's own clause.
Match? _outerMatch(RegExp pattern, String sql) {
  final matches = _topLevelMatches(pattern, sql);
  return matches.isEmpty ? null : matches.last;
}

/// Injects or clamps a `LIMIT` on read-only queries (`SELECT`, `WITH`, `VALUES`).
///
/// - No `LIMIT` / `FETCH … ONLY` → appends `LIMIT [limit]`.
/// - `LIMIT ALL` → replaced with `LIMIT [limit]`.
/// - `LIMIT n [OFFSET m]` where `n > limit` → clamped to [limit].
/// - `FETCH FIRST/NEXT n ROWS ONLY` where `n > limit` → clamped.
/// - Non-select statements are returned unchanged.
///
/// Only the outer query's `LIMIT` / `FETCH` counts: clauses inside parentheses
/// (CTEs, subqueries) and text inside literals or comments are ignored, and
/// leading `--` / `/* */` comments do not hide the statement kind.
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

  final limitAllMatch = _outerMatch(_limitAll, sql);
  if (limitAllMatch != null) {
    return sql.replaceRange(
      limitAllMatch.start,
      limitAllMatch.end,
      'LIMIT $limit',
    );
  }

  final limitMatch = _outerMatch(_limitCount, sql);
  if (limitMatch != null) {
    final existing = int.tryParse(limitMatch.group(1)!);
    if (existing == null || existing <= limit) {
      return sql;
    }
    final offsetPart = limitMatch.group(2) ?? '';
    return sql.replaceRange(
      limitMatch.start,
      limitMatch.end,
      'LIMIT $limit$offsetPart',
    );
  }

  final fetchMatch = _outerMatch(_fetchFirst, sql);
  if (fetchMatch != null) {
    final existing = int.tryParse(fetchMatch.group(1)!);
    if (existing == null || existing <= limit) {
      return sql;
    }
    return sql.replaceRange(
      fetchMatch.start,
      fetchMatch.end,
      'FETCH FIRST $limit ROWS ONLY',
    );
  }

  if (_outerMatch(RegExp(r'\bLIMIT\b', caseSensitive: false), sql) != null ||
      _outerMatch(RegExp(r'\bFETCH\b', caseSensitive: false), sql) != null) {
    // Unrecognized LIMIT/FETCH shape — leave unchanged.
    return sql;
  }

  // Insert before trailing `;` / whitespace / comments (a trailing `-- note`
  // must not swallow or precede the clause).
  final masked = maskSqlLiteralsForLimitScan(sql, keepLiterals: true);
  var end = masked.length;
  while (end > 0) {
    final ch = masked[end - 1];
    if (ch == ';' || ch.trim().isEmpty) {
      end--;
    } else {
      break;
    }
  }
  final body = sql.substring(0, end);
  final tail = sql.substring(end);
  final tailIsPlain = tail.replaceAll(RegExp(r'[;\s]'), '').isEmpty;
  // Plain `;` / whitespace tails are normalized to their semicolons; a tail
  // with comments is kept verbatim after the clause.
  final suffix = tailIsPlain ? ';' * ';'.allMatches(tail).length : tail;

  return '$body\nLIMIT $limit$suffix';
}
