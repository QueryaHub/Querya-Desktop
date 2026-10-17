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
}
