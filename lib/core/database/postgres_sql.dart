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
