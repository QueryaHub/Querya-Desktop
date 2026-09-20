/// Comment-strip + first-keyword classification for SQLite (not a full parser).

/// Strips `--` line comments and `/* */` block comments.
String sqliteStripSqlComments(String sql) {
  return sql
      .replaceAll(RegExp(r'--.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
}

/// Whether [sql] should use `rawQuery` and is allowed on a read-only connection.
///
/// `WITH` is read-only only when the statement after the CTEs is `SELECT` /
/// `VALUES` / `EXPLAIN`. `PRAGMA name = value` is a write.
bool sqliteSqlIsReadOnlyQuery(String sql) {
  final stmt = sqliteStripSqlComments(sql).trim().toLowerCase();
  if (stmt.isEmpty) return true;

  final scan = _SqliteSqlScan(stmt);
  scan.skipWsAndSemis();
  final kw = scan.peekKeyword();
  if (kw == null) return false;

  switch (kw) {
    case 'select':
    case 'values':
    case 'explain':
      return true;
    case 'pragma':
      return !_pragmaAssigns(scan);
    case 'with':
      if (!_skipWithCtes(scan)) return false;
      final inner = scan.peekKeyword();
      return inner == 'select' || inner == 'values' || inner == 'explain';
    default:
      return false;
  }
}

bool _pragmaAssigns(_SqliteSqlScan scan) {
  scan.eatKeyword('pragma');
  var depth = 0;
  while (scan.i < scan.s.length) {
    final c = scan.s[scan.i];
    if (c == "'" || c == '"' || c == '`') {
      scan.skipQuoted(c);
      continue;
    }
    if (c == '[') {
      scan.skipUntil(']');
      continue;
    }
    if (c == '(') {
      depth++;
      scan.i++;
      continue;
    }
    if (c == ')') {
      if (depth > 0) depth--;
      scan.i++;
      continue;
    }
    if (c == ';' && depth == 0) break;
    if (c == '=' && depth == 0) return true;
    scan.i++;
  }
  return false;
}

bool _skipWithCtes(_SqliteSqlScan scan) {
  if (!scan.eatKeyword('with')) return false;
  scan.eatKeyword('recursive');
  while (true) {
    if (!scan.skipIdent()) return false;
    scan.skipWs();
    if (scan.peek('(')) {
      if (!scan.skipBalancedParen()) return false;
    }
    if (!scan.eatKeyword('as')) return false;
    if (scan.eatKeyword('not')) {
      if (!scan.eatKeyword('materialized')) return false;
    } else {
      scan.eatKeyword('materialized');
    }
    if (!scan.skipBalancedParen()) return false;
    scan.skipWs();
    if (scan.peek(',')) {
      scan.i++;
      continue;
    }
    return true;
  }
}

class _SqliteSqlScan {
  _SqliteSqlScan(this.s);

  final String s;
  int i = 0;

  void skipWs() {
    while (i < s.length) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || c == 0x09 || c == 0x0a || c == 0x0d) {
        i++;
        continue;
      }
      break;
    }
  }

  void skipWsAndSemis() {
    skipWs();
    while (i < s.length && s[i] == ';') {
      i++;
      skipWs();
    }
  }

  bool peek(String ch) {
    skipWs();
    return i < s.length && s[i] == ch;
  }

  String? peekKeyword() {
    skipWs();
    if (i >= s.length) return null;
    final c = s.codeUnitAt(i);
    if (!_isIdentStart(c)) return null;
    var j = i + 1;
    while (j < s.length && _isIdentPart(s.codeUnitAt(j))) {
      j++;
    }
    return s.substring(i, j);
  }

  bool eatKeyword(String kw) {
    skipWs();
    if (i + kw.length > s.length) return false;
    if (s.substring(i, i + kw.length) != kw) return false;
    final end = i + kw.length;
    if (end < s.length && _isIdentPart(s.codeUnitAt(end))) return false;
    i = end;
    return true;
  }

  bool skipIdent() {
    skipWs();
    if (i >= s.length) return false;
    final c = s[i];
    if (c == '"' || c == '`') {
      skipQuoted(c);
      return true;
    }
    if (c == '[') {
      skipUntil(']');
      return true;
    }
    if (!_isIdentStart(s.codeUnitAt(i))) return false;
    i++;
    while (i < s.length && _isIdentPart(s.codeUnitAt(i))) {
      i++;
    }
    return true;
  }

  bool skipBalancedParen() {
    skipWs();
    if (i >= s.length || s[i] != '(') return false;
    var depth = 0;
    while (i < s.length) {
      final c = s[i];
      if (c == "'" || c == '"' || c == '`') {
        skipQuoted(c);
        continue;
      }
      if (c == '[') {
        skipUntil(']');
        continue;
      }
      if (c == '(') {
        depth++;
        i++;
        continue;
      }
      if (c == ')') {
        depth--;
        i++;
        if (depth == 0) return true;
        continue;
      }
      i++;
    }
    return false;
  }

  void skipQuoted(String quote) {
    i++;
    while (i < s.length) {
      if (s[i] == quote) {
        i++;
        if (i < s.length && s[i] == quote) {
          i++;
          continue;
        }
        return;
      }
      i++;
    }
  }

  void skipUntil(String end) {
    i++;
    while (i < s.length) {
      if (s[i] == end) {
        i++;
        return;
      }
      i++;
    }
  }
}

bool _isIdentStart(int c) => (c >= 0x61 && c <= 0x7a) || c == 0x5f;

bool _isIdentPart(int c) => _isIdentStart(c) || (c >= 0x30 && c <= 0x39);
