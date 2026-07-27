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

/// Masks SQL string / identifier / dollar-quoted literals with spaces so
/// keyword regexes do not match inside quotes (same length, same offsets).
String maskSqlLiteralsForLimitScan(String sql) {
  final out = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    final c = sql.codeUnitAt(i);

    // Single-quoted string; '' is an escaped quote.
    if (c == 0x27 /* ' */) {
      out.write(' ');
      i++;
      while (i < sql.length) {
        out.write(' ');
        if (sql.codeUnitAt(i) == 0x27) {
          if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x27) {
            out.write(' ');
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
      continue;
    }

    // Double-quoted identifier.
    if (c == 0x22 /* " */) {
      out.write(' ');
      i++;
      while (i < sql.length) {
        out.write(' ');
        if (sql.codeUnitAt(i) == 0x22) {
          if (i + 1 < sql.length && sql.codeUnitAt(i + 1) == 0x22) {
            out.write(' ');
            i += 2;
            continue;
          }
          i++;
          break;
        }
        i++;
      }
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
          out.write(' ' * (end - i));
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

Match? _firstMatchOutsideLiterals(RegExp pattern, String sql) {
  final masked = maskSqlLiteralsForLimitScan(sql);
  return pattern.firstMatch(masked);
}

bool _hasMatchOutsideLiterals(RegExp pattern, String sql) {
  return _firstMatchOutsideLiterals(pattern, sql) != null;
}

/// Injects or clamps a `LIMIT` on read-only queries (`SELECT`, `WITH`, `VALUES`).
///
/// - No `LIMIT` / `FETCH … ONLY` → appends `LIMIT [limit]`.
/// - `LIMIT ALL` → replaced with `LIMIT [limit]`.
/// - `LIMIT n [OFFSET m]` where `n > limit` → clamped to [limit].
/// - `FETCH FIRST/NEXT n ROWS ONLY` where `n > limit` → clamped.
/// - Non-select statements are returned unchanged.
///
/// Matches ignore `LIMIT` / `FETCH` text inside string or quoted identifiers.
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

  final limitAllMatch = _firstMatchOutsideLiterals(_limitAll, sql);
  if (limitAllMatch != null) {
    return sql.replaceRange(
      limitAllMatch.start,
      limitAllMatch.end,
      'LIMIT $limit',
    );
  }

  final limitMatch = _firstMatchOutsideLiterals(_limitCount, sql);
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

  final fetchMatch = _firstMatchOutsideLiterals(_fetchFirst, sql);
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

  if (_hasMatchOutsideLiterals(RegExp(r'\bLIMIT\b', caseSensitive: false), sql) ||
      _hasMatchOutsideLiterals(RegExp(r'\bFETCH\b', caseSensitive: false), sql)) {
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
