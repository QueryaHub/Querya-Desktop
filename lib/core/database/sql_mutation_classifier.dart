import 'package:querya_desktop/core/database/destructive_sql_detector.dart';

const _mutatingKeywords = {
  'INSERT', 'UPDATE', 'DELETE', 'REPLACE', 'MERGE', 'TRUNCATE', 'DROP',
  'ALTER', 'CREATE', 'RENAME', 'GRANT', 'REVOKE',
};

final _firstWord = RegExp(r'^\(*\s*([A-Za-z]+)');
final _dataModifyingCte = RegExp(r'\b(INSERT|UPDATE|DELETE|MERGE)\b');

/// Whether a single SQL [statement] changes data or schema (DML / DDL).
///
/// Comments and string literals are ignored. `WITH ...` statements count when
/// a data-modifying statement appears inside them.
///
/// [backslashEscapes]: whether `\'` escapes a quote (MySQL; the default), see
/// [DestructiveSqlDetector.stripCommentsAndStrings].
bool isMutatingSqlStatement(String statement, {bool backslashEscapes = true}) {
  final sanitized = DestructiveSqlDetector.stripCommentsAndStrings(
    statement,
    backslashEscapes: backslashEscapes,
  ).trim();
  if (sanitized.isEmpty) return false;
  final upper = sanitized.toUpperCase();
  final first = _firstWord.firstMatch(upper)?.group(1);
  if (first == null) return false;
  if (_mutatingKeywords.contains(first)) return true;
  if (first == 'WITH') return _dataModifyingCte.hasMatch(upper);
  return false;
}

/// Whether the SQL script [sql] contains at least one mutating statement.
bool containsMutatingSql(String sql, {bool backslashEscapes = true}) =>
    DestructiveSqlDetector.splitStatements(
      sql,
      backslashEscapes: backslashEscapes,
    ).any((s) => isMutatingSqlStatement(s, backslashEscapes: backslashEscapes));

/// Statements other than DML / DDL that still write, run code or touch the
/// server's files.
const _readOnlyRefusedFirstWords = {
  'CALL', 'DO', 'COPY', 'LOAD', 'REFRESH', 'COMMENT', 'VACUUM', 'REINDEX',
  'CLUSTER', 'LOCK', 'IMPORT',
};

final _readOnlyEscape = RegExp(
  r'\bREAD\s+WRITE\b|'
  r'\b(?:DEFAULT_)?TRANSACTION_READ_ONLY\b|\bTX_READ_ONLY\b|\bREAD_ONLY\b',
);
final _setConfig = RegExp(r'\bSET_CONFIG\s*\(');
final _explainAnalyze = RegExp(r'^EXPLAIN\s+(?:\(?[^)]*\b)?ANALY[SZ]E\b');

/// Why the Read-only mode of the SQL editor refuses [statement], or null when
/// it may run. Covers what [isMutatingSqlStatement] does and the ways a script
/// could switch the session back to read-write (`SET ... transaction_read_only`,
/// `BEGIN READ WRITE`, `SET TRANSACTION READ WRITE`, `set_config(...)`), plus
/// `EXPLAIN ANALYZE` of a write and statements that run code or write files.
String? readOnlyRefusal(String statement, {bool backslashEscapes = true}) {
  final upper = DestructiveSqlDetector.stripCommentsAndStrings(
    statement,
    backslashEscapes: backslashEscapes,
  ).trim().toUpperCase();
  if (upper.isEmpty) return null;
  final first = _firstWord.firstMatch(upper)?.group(1);
  if (first == null) return null;
  if (_explainAnalyze.hasMatch(upper) && _dataModifyingCte.hasMatch(upper)) {
    return 'EXPLAIN ANALYZE of a data-modifying statement would run it';
  }
  if (isMutatingSqlStatement(statement, backslashEscapes: backslashEscapes)) {
    return 'it changes data or schema';
  }
  if (_readOnlyRefusedFirstWords.contains(first)) {
    return '$first can write or run code';
  }
  // `READ_ONLY` as a column name in a SELECT is fine; only the statements that
  // set a session or transaction mode count.
  final setsMode = first == 'SET' || first == 'BEGIN' || first == 'START';
  if ((setsMode && _readOnlyEscape.hasMatch(upper)) ||
      _setConfig.hasMatch(upper)) {
    return 'it would switch the session out of read-only';
  }
  return null;
}

/// The first reason in [sql] (a script) that Read-only mode refuses, or null.
String? readOnlyScriptRefusal(String sql, {bool backslashEscapes = true}) {
  for (final statement in DestructiveSqlDetector.splitStatements(
    sql,
    backslashEscapes: backslashEscapes,
  )) {
    final why = readOnlyRefusal(statement, backslashEscapes: backslashEscapes);
    if (why != null) return why;
  }
  return null;
}
