import 'dart:convert';

import 'package:postgres/postgres.dart' show ServerException;

/// A failed query as the results pane shows it (#1557): one readable line,
/// and the driver's text without the statement the app wrapped around the
/// user's SQL.
class QueryErrorText {
  const QueryErrorText({required this.summary, required this.detail});

  /// Reads [raw], the `toString()` of whatever the driver threw.
  factory QueryErrorText.parse(String raw) {
    final detail = _unwrap(raw.trim());
    return QueryErrorText(summary: _summary(detail), detail: detail);
  }

  /// The driver's message alone: `no such column: u.name`.
  final String summary;

  /// The whole driver text, minus the app's own wrapping.
  final String detail;

  /// Whether [detail] says more than [summary].
  bool get hasDetail => detail != summary;

  static const _maxSummary = 300;

  // SQLite (sqlite3): `SqliteException(1): while preparing statement, <msg>,
  // SQL logic error (code 1)`.
  static final _sqlite = RegExp(
    r'SqliteException\(\d+\): (?:while [^,\n]+, )?([^\n]+?)'
    r'(?:, [^,\n]*\(code \d+\))?(?:\n|$)',
  );

  // PostgreSQL (postgres 3): `Severity.error 42703: column "x" does not exist
  // detail: ... hint: ...`.
  static final _postgres = RegExp(
    r'\b(?:Severity\.)?(?:error|fatal|panic|ERROR|FATAL|PANIC) '
    r'[0-9A-Z]{5}: ([^\n]+?)(?= (?:detail|hint|table|column|constraint)\b|\n|$)',
  );

  // MySQL (mysql_client): `MySQLServerException [1054]: Unknown column ...`.
  static final _mysql = RegExp(r'MySQLServerException \[\d+\]: ([^\n]+)');

  /// The `SELECT * FROM (\n<sql>\n)` that keeps SQLite column names unique
  /// (#1144), with the row limit the app adds after it.
  static final _wrapper = RegExp(
    r'SELECT \* FROM \(\n([\s\S]*?)\n\)(?:\s*LIMIT \d+(?:\s+OFFSET \d+)?)?',
  );

  // Offsets count from the start of the wrapper, not of the user's text.
  static final _position = RegExp(r' \(at position \d+\)');

  static String _unwrap(String raw) {
    if (!_wrapper.hasMatch(raw)) return raw;
    return raw
        .replaceAllMapped(_wrapper, (m) => m[1]!)
        .replaceAll(_position, '');
  }

  static String _summary(String detail) {
    for (final pattern in [_sqlite, _postgres, _mysql]) {
      final m = pattern.firstMatch(detail);
      final message = m?.group(1)?.trim();
      if (message != null && message.isNotEmpty) return _cap(message);
    }
    final first = detail
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => detail);
    return _cap(first.startsWith('Exception: ') ? first.substring(11) : first);
  }

  static String _cap(String s) =>
      s.length <= _maxSummary ? s : '${s.substring(0, _maxSummary)}…';

  /// `SELECT * FROM (\n` the wrapper puts before the user's SQL.
  static const _wrapperPrefix = 'SELECT * FROM (\n';

  // SQLite: `Causing statement (at position 29): ...`, a byte offset into the
  // statement the driver prepared.
  static final _sqlitePosition = RegExp(r'\(at position (\d+)\)');

  /// Where in [sql], the text that was sent, the error is: a 0-based offset in
  /// characters, or null when the driver does not say (MySQL) or the place is
  /// not in [sql].
  ///
  /// PostgreSQL gives a 1-based character position in the statement; SQLite a
  /// byte offset in the statement it prepared, which is the user's SQL inside
  /// the app's wrapper when [sql] is a query (#1144), so the wrapper's prefix
  /// is taken off. The row limit the app appends comes after the text, so it
  /// does not move anything.
  static int? offsetIn(Object error, String sql) {
    if (error is ServerException) return offsetOfPgPosition(error.position, sql);
    final text = error.toString();
    final m = _sqlitePosition.firstMatch(text);
    if (m == null) return null;
    var bytes = int.parse(m[1]!);
    if (text.contains(_wrapperPrefix)) bytes -= _wrapperPrefix.length;
    if (bytes < 0) return null;
    final encoded = utf8.encode(sql);
    if (bytes > encoded.length) return null;
    return utf8.decode(encoded.sublist(0, bytes), allowMalformed: true).length;
  }

  /// The offset in [sql] of a PostgreSQL `position` (1-based, in characters),
  /// or null when there is none or it lies outside [sql].
  static int? offsetOfPgPosition(int? position, String sql) {
    if (position == null) return null;
    final offset = position - 1;
    return offset >= 0 && offset <= sql.length ? offset : null;
  }
}
