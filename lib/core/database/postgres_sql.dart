// Helpers for ad-hoc SQL workspace (transactions, stripping comments).

import 'sql_limit.dart';

export 'sql_limit.dart'
    show injectSqlLimit, stripLeadingWhitespaceAndLineComments;

/// True if the first statement looks like explicit transaction control, so we
/// should not prepend `BEGIN` when autocommit is off.
bool shouldSkipImplicitBegin(String sql) {
  final s = stripLeadingWhitespaceAndLineComments(sql);
  if (s.isEmpty) return true;
  final u = s.toUpperCase();

  if (u.startsWith('START TRANSACTION')) return true;
  if (u.startsWith('BEGIN')) return true;
  if (u.startsWith('COMMIT')) return true;
  if (u.startsWith('ROLLBACK')) return true;
  if (u.startsWith('SAVEPOINT')) return true;
  if (u.startsWith('RELEASE SAVEPOINT')) return true;
  if (u.startsWith('RELEASE ')) return true;
  if (u.startsWith('PREPARE TRANSACTION')) return true;
  if (u.startsWith('COMMIT PREPARED')) return true;
  if (u.startsWith('ROLLBACK PREPARED')) return true;
  if (u.startsWith('END')) return true;

  return false;
}

/// Own-backend `xact_start` (set at `BEGIN`, even when no XID is assigned).
///
/// Replaces `pg_current_xact_id_if_assigned()` (PG 13+), which stays NULL after
/// `BEGIN` + `SELECT`. `pg_stat_activity.xact_start` exists on PG 9+.
const kPostgresOpenTransactionProbeSql =
    'SELECT xact_start IS NOT NULL '
    'FROM pg_catalog.pg_stat_activity '
    'WHERE pid = pg_backend_pid()';

/// Updates session tx state from a successfully executed statement.
///
/// `BEGIN` / `START TRANSACTION` open; `COMMIT` / `END` / `ROLLBACK` close.
/// `ROLLBACK TO` (savepoint) leaves the transaction open.
bool applyPostgresTransactionSql(bool currentlyOpen, String sql) {
  final s = stripLeadingWhitespaceAndLineComments(sql);
  if (s.isEmpty) return currentlyOpen;
  final u = s.toUpperCase();

  if (u.startsWith('START TRANSACTION') || _pgTxStartsWithKeyword(u, 'BEGIN')) {
    return true;
  }
  if (_pgTxStartsWithKeyword(u, 'COMMIT') || _pgTxStartsWithKeyword(u, 'END')) {
    return false;
  }
  if (_pgTxStartsWithKeyword(u, 'ROLLBACK')) {
    if (RegExp(r'^ROLLBACK\s+TO\b').hasMatch(u)) return currentlyOpen;
    return false;
  }
  return currentlyOpen;
}

bool _pgTxStartsWithKeyword(String upper, String kw) {
  if (!upper.startsWith(kw)) return false;
  if (upper.length == kw.length) return true;
  final next = upper.codeUnitAt(kw.length);
  final isIdent = (next >= 0x41 && next <= 0x5a) ||
      next == 0x5f ||
      (next >= 0x30 && next <= 0x39);
  return !isIdent;
}

/// Runs [statements] as separate extended-protocol executes inside BEGIN/COMMIT.
///
/// PostgreSQL Parse cannot contain multiple commands, so
/// `BEGIN; UPDATE …; COMMIT;` in one [execute] fails.
Future<void> runPostgresStatementsInTransaction(
  Future<void> Function(String sql) execute,
  Iterable<String> statements,
) async {
  await execute('BEGIN');
  try {
    for (final sql in statements) {
      await execute(sql);
    }
    await execute('COMMIT');
  } catch (_) {
    try {
      await execute('ROLLBACK');
    } catch (_) {}
    rethrow;
  }
}
