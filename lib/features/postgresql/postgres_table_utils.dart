/// Utilities for PostgreSQL table data view (quoting, row conversion).
library;

import 'package:querya_desktop/core/database/postgres_result_cells.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';

/// Default page size for table browse and the SQL template filled from the tree.
const kPostgresBrowseDefaultRowLimit = 200;

/// Browse SELECT for Table Browser. PK columns get `ORDER BY` so LIMIT/OFFSET
/// is stable. Empty [primaryKeys] keeps unordered scan (views / no PK).
String postgresBrowseDataSql({
  required String qualifiedFrom,
  required List<String> primaryKeys,
  required int limit,
  required int offset,
}) {
  final order = primaryKeys.isEmpty
      ? ''
      : ' ORDER BY ${primaryKeys.map(quotePostgresIdentifier).join(', ')}';
  return 'SELECT * FROM $qualifiedFrom$order LIMIT $limit OFFSET $offset';
}

/// `SELECT *` template matching [PostgresTableView] browse (same limit/offset).
String postgresBrowseSelectSql({
  required String schema,
  required String table,
  int limit = kPostgresBrowseDefaultRowLimit,
}) {
  String q(String name) => quotePostgresIdentifier(name);
  return 'SELECT * FROM ${q(schema)}.${q(table)} LIMIT $limit OFFSET 0;\n';
}

/// Quotes a PostgreSQL identifier (e.g. schema or table name).
/// Doubles any internal double-quote.
String quotePostgresIdentifier(String name) {
  return '"${name.replaceAll('"', '""')}"';
}

/// Converts raw result rows (list of dynamic values per row) to list of string rows.
List<List<String>> convertResultRowsToStrings(List<List<dynamic>> rawRows) {
  return [
    for (final row in rawRows)
      [for (final value in row) postgresResultCellToDisplayString(value)],
  ];
}

/// Whether [sql] is allowed for the Table Browser custom-SQL dialog.
///
/// Classifies the **first** statement after comments (not substring `contains`).
/// Allows `SELECT` / `WITH … SELECT` / `TABLE` / `VALUES` / `(SELECT …)` only.
/// Multi-statement scripts are rejected.
bool isAllowedPostgresSelectQuery(String sql) {
  final t = sql.trim();
  if (t.isEmpty) return false;

  final statements = _splitPostgresStatements(t)
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty && !_postgresFragmentIsOnlyComments(s))
      .toList();
  if (statements.length != 1) return false;

  return _postgresStatementIsReadOnlySelect(statements.first);
}

List<String> _splitPostgresStatements(String sql) {
  final masked = _maskPostgresComments(maskSqlLiteralsForLimitScan(sql));
  final statements = <String>[];
  var start = 0;
  for (var i = 0; i < masked.length; i++) {
    if (masked[i] == ';') {
      statements.add(sql.substring(start, i));
      start = i + 1;
    }
  }
  statements.add(sql.substring(start));
  return statements;
}

String _maskPostgresComments(String sql) {
  final out = StringBuffer();
  var i = 0;
  while (i < sql.length) {
    if (i + 1 < sql.length && sql[i] == '-' && sql[i + 1] == '-') {
      while (i < sql.length && sql[i] != '\n') {
        out.write(' ');
        i++;
      }
      continue;
    }
    if (i + 1 < sql.length && sql[i] == '/' && sql[i + 1] == '*') {
      out.write('  ');
      i += 2;
      while (i < sql.length) {
        if (i + 1 < sql.length && sql[i] == '*' && sql[i + 1] == '/') {
          out.write('  ');
          i += 2;
          break;
        }
        out.write(' ');
        i++;
      }
      continue;
    }
    out.write(sql[i]);
    i++;
  }
  return out.toString();
}

bool _postgresFragmentIsOnlyComments(String sql) {
  var s = sql.trim();
  while (s.isNotEmpty) {
    s = stripLeadingWhitespaceAndLineComments(s).trimLeft();
    if (s.startsWith('/*')) {
      final end = s.indexOf('*/');
      if (end == -1) return true;
      s = s.substring(end + 2).trim();
      continue;
    }
    if (s.isEmpty || s == ';') return true;
    return false;
  }
  return true;
}

bool _postgresStatementIsReadOnlySelect(String sql) {
  final code = _postgresLeadingCode(sql);
  if (code.isEmpty) return false;
  final u = code.toUpperCase();
  if (_startsWithKeyword(u, 'SELECT')) return true;
  if (_startsWithKeyword(u, 'VALUES')) return true;
  if (_startsWithKeyword(u, 'TABLE')) return true;
  if (_startsWithKeyword(u, 'WITH')) {
    return _postgresWithIsSelect(_stripPostgresComments(code));
  }
  return false;
}

String _postgresLeadingCode(String sql) {
  var s = sql.trim();
  while (s.isNotEmpty) {
    s = stripLeadingWhitespaceAndLineComments(s).trimLeft();
    if (s.startsWith('/*')) {
      final end = s.indexOf('*/');
      if (end == -1) return '';
      s = s.substring(end + 2).trimLeft();
      continue;
    }
    if (s.startsWith('(')) {
      s = s.substring(1).trimLeft();
      continue;
    }
    return s;
  }
  return '';
}

bool _startsWithKeyword(String upper, String kw) {
  if (!upper.startsWith(kw)) return false;
  if (upper.length == kw.length) return true;
  final next = upper.codeUnitAt(kw.length);
  final isIdent = (next >= 0x41 && next <= 0x5a) ||
      next == 0x5f ||
      (next >= 0x30 && next <= 0x39);
  return !isIdent;
}

String _stripPostgresComments(String sql) {
  return sql
      .replaceAll(RegExp(r'--.*$', multiLine: true), '')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
}

/// `WITH` is read-only only when the statement after the CTEs is SELECT/VALUES/TABLE.
bool _postgresWithIsSelect(String sql) {
  final scan = _PgSqlScan(sql.toLowerCase());
  if (!_skipPostgresWithCtes(scan)) return false;
  final inner = scan.peekKeyword();
  return inner == 'select' || inner == 'values' || inner == 'table';
}

bool _skipPostgresWithCtes(_PgSqlScan scan) {
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

class _PgSqlScan {
  _PgSqlScan(this.s);

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

  bool peek(String ch) {
    skipWs();
    return i < s.length && s[i] == ch;
  }

  String? peekKeyword() {
    skipWs();
    if (i >= s.length) return null;
    final c = s.codeUnitAt(i);
    if (!_pgIdentStart(c)) return null;
    var j = i + 1;
    while (j < s.length && _pgIdentPart(s.codeUnitAt(j))) {
      j++;
    }
    return s.substring(i, j);
  }

  bool eatKeyword(String kw) {
    skipWs();
    if (i + kw.length > s.length) return false;
    if (s.substring(i, i + kw.length) != kw) return false;
    final end = i + kw.length;
    if (end < s.length && _pgIdentPart(s.codeUnitAt(end))) return false;
    i = end;
    return true;
  }

  bool skipIdent() {
    skipWs();
    if (i >= s.length) return false;
    if (s[i] == '"') {
      i++;
      while (i < s.length) {
        if (s[i] == '"') {
          i++;
          if (i < s.length && s[i] == '"') {
            i++;
            continue;
          }
          return true;
        }
        i++;
      }
      return true;
    }
    if (!_pgIdentStart(s.codeUnitAt(i))) return false;
    i++;
    while (i < s.length && _pgIdentPart(s.codeUnitAt(i))) {
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
      if (c == "'" || c == '"') {
        final q = c;
        i++;
        while (i < s.length) {
          if (s[i] == q) {
            i++;
            if (i < s.length && s[i] == q) {
              i++;
              continue;
            }
            break;
          }
          i++;
        }
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
}

bool _pgIdentStart(int c) => (c >= 0x61 && c <= 0x7a) || c == 0x5f;

bool _pgIdentPart(int c) => _pgIdentStart(c) || (c >= 0x30 && c <= 0x39);
