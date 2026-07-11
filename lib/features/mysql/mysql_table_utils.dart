/// Whether [sql] is allowed for the table browser "custom SQL" path (read-only SELECT).
bool isAllowedMysqlSelectQuery(String sql) {
  final t = sql.trim();
  if (t.isEmpty) return false;
  final lower = t.toLowerCase();
  if (!lower.startsWith('select') && !lower.startsWith('with')) {
    return false;
  }

  final statements = _splitMysqlStatements(t)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_mysqlFragmentIsOnlyComments(s))
      .toList();
  if (statements.length != 1) return false;

  return !_mysqlSelectQueryHasBlockedConstructs(statements.first);
}

List<String> _splitMysqlStatements(String sql) {
  final statements = <String>[];
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inBacktick = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      buffer.write(c);
      if (c == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      buffer.write(c);
      if (c == '*' && next == '/') {
        buffer.write(next);
        inBlockComment = false;
        i++;
      }
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && !inBacktick) {
      if (c == '-' && next == '-') {
        inLineComment = true;
        buffer.write(c);
        buffer.write(next);
        i++;
        continue;
      }
      if (c == '#') {
        inLineComment = true;
        buffer.write(c);
        continue;
      }
      if (c == '/' && next == '*') {
        inBlockComment = true;
        buffer.write(c);
        buffer.write(next);
        i++;
        continue;
      }
    }

    if (!inDoubleQuote && !inBacktick && c == "'") {
      if (inSingleQuote && next == "'") {
        buffer.write(c);
        buffer.write(next);
        i++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      buffer.write(c);
      continue;
    }

    if (!inSingleQuote && !inBacktick && c == '"') {
      if (inDoubleQuote && next == '"') {
        buffer.write(c);
        buffer.write(next);
        i++;
        continue;
      }
      inDoubleQuote = !inDoubleQuote;
      buffer.write(c);
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && c == '`') {
      inBacktick = !inBacktick;
      buffer.write(c);
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && !inBacktick && c == ';') {
      statements.add(buffer.toString());
      buffer.clear();
      continue;
    }

    buffer.write(c);
  }

  statements.add(buffer.toString());
  return statements;
}

bool _mysqlFragmentIsOnlyComments(String sql) {
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inBacktick = false;
  var inLineComment = false;
  var inBlockComment = false;
  var hasCode = false;

  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      if (c == '\n') inLineComment = false;
      continue;
    }
    if (inBlockComment) {
      if (c == '*' && next == '/') {
        inBlockComment = false;
        i++;
      }
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && !inBacktick) {
      if (c == '-' && next == '-') {
        inLineComment = true;
        i++;
        continue;
      }
      if (c == '#') {
        inLineComment = true;
        continue;
      }
      if (c == '/' && next == '*') {
        inBlockComment = true;
        i++;
        continue;
      }
    }

    if (!inDoubleQuote && !inBacktick && c == "'") {
      if (inSingleQuote && next == "'") {
        i++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      continue;
    }

    if (!inSingleQuote && !inBacktick && c == '"') {
      if (inDoubleQuote && next == '"') {
        i++;
        continue;
      }
      inDoubleQuote = !inDoubleQuote;
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && c == '`') {
      inBacktick = !inBacktick;
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && !inBacktick && !_isWhitespace(c)) {
      hasCode = true;
      break;
    }
  }

  return !hasCode;
}

bool _mysqlSelectQueryHasBlockedConstructs(String sql) {
  final masked = _maskMysqlLiteralsAndComments(sql).toLowerCase();
  final blocked = [
    RegExp(r'\binto\s+outfile\b'),
    RegExp(r'\binto\s+dumpfile\b'),
    RegExp(r'\bfor\s+update\b'),
    RegExp(r'\block\s+in\s+share\s+mode\b'),
    RegExp(
      r'\b(insert|update|delete|drop|truncate|alter|create|grant|revoke|call|execute|replace|rename)\b',
    ),
  ];
  for (final pattern in blocked) {
    if (pattern.hasMatch(masked)) return true;
  }
  return false;
}

String _maskMysqlLiteralsAndComments(String sql) {
  final buffer = StringBuffer();
  var inSingleQuote = false;
  var inDoubleQuote = false;
  var inBacktick = false;
  var inLineComment = false;
  var inBlockComment = false;

  for (var i = 0; i < sql.length; i++) {
    final c = sql[i];
    final next = i + 1 < sql.length ? sql[i + 1] : '';

    if (inLineComment) {
      buffer.write(' ');
      if (c == '\n') {
        buffer.write('\n');
        inLineComment = false;
      }
      continue;
    }
    if (inBlockComment) {
      buffer.write(c == '\n' ? '\n' : ' ');
      if (c == '*' && next == '/') {
        buffer.write(' ');
        inBlockComment = false;
        i++;
      }
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && !inBacktick) {
      if (c == '-' && next == '-') {
        inLineComment = true;
        buffer.write(' ');
        buffer.write(' ');
        i++;
        continue;
      }
      if (c == '#') {
        inLineComment = true;
        buffer.write(' ');
        continue;
      }
      if (c == '/' && next == '*') {
        inBlockComment = true;
        buffer.write(' ');
        buffer.write(' ');
        i++;
        continue;
      }
    }

    if (!inDoubleQuote && !inBacktick && c == "'") {
      if (inSingleQuote && next == "'") {
        buffer.write(' ');
        buffer.write(' ');
        i++;
        continue;
      }
      inSingleQuote = !inSingleQuote;
      buffer.write(' ');
      continue;
    }

    if (!inSingleQuote && !inBacktick && c == '"') {
      if (inDoubleQuote && next == '"') {
        buffer.write(' ');
        buffer.write(' ');
        i++;
        continue;
      }
      inDoubleQuote = !inDoubleQuote;
      buffer.write(' ');
      continue;
    }

    if (!inSingleQuote && !inDoubleQuote && c == '`') {
      inBacktick = !inBacktick;
      buffer.write(' ');
      continue;
    }

    if (inSingleQuote || inDoubleQuote || inBacktick) {
      buffer.write(' ');
      continue;
    }

    buffer.write(c);
  }

  return buffer.toString();
}

bool _isWhitespace(String c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}
