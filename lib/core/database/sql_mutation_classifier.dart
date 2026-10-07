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
bool isMutatingSqlStatement(String statement) {
  final sanitized =
      DestructiveSqlDetector.stripCommentsAndStrings(statement).trim();
  if (sanitized.isEmpty) return false;
  final upper = sanitized.toUpperCase();
  final first = _firstWord.firstMatch(upper)?.group(1);
  if (first == null) return false;
  if (_mutatingKeywords.contains(first)) return true;
  if (first == 'WITH') return _dataModifyingCte.hasMatch(upper);
  return false;
}

/// Whether the SQL script [sql] contains at least one mutating statement.
bool containsMutatingSql(String sql) => DestructiveSqlDetector
    .splitStatements(sql)
    .any(isMutatingSqlStatement);
