/// Result of extracting target table and schema from an SQL query.
class SqlTableTarget {
  const SqlTableTarget({
    required this.tableName,
    this.schema,
  });

  final String tableName;
  final String? schema;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SqlTableTarget &&
          tableName == other.tableName &&
          schema == other.schema;

  @override
  int get hashCode => Object.hash(tableName, schema);
}

/// Helper utility to infer the primary target table from a simple SELECT query.
abstract final class SqlTableTargetExtractor {
  static const _fromFollowers = {
    'where',
    'group',
    'order',
    'limit',
    'offset',
    'having',
    'window',
    'fetch',
    'for',
    'union',
    'except',
    'intersect',
    'returning',
    'on',
    'using',
  };

  static const _joinStarters = {
    'join',
    'inner',
    'left',
    'right',
    'full',
    'cross',
    'natural',
  };

  /// Extracts the target schema and table name from [sql].
  ///
  /// Returns `null` if no simple single-table target can be determined
  /// (JOIN, comma-FROM, subquery, VALUES, set operations, CTE).
  static SqlTableTarget? extract(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) return null;
    if (_startsWithKeyword(trimmed, 'with')) return null;
    if (_indexOfTopLevelKeyword(trimmed, 'join') >= 0) return null;
    if (_indexOfTopLevelKeyword(trimmed, 'union') >= 0) return null;
    if (_indexOfTopLevelKeyword(trimmed, 'except') >= 0) return null;
    if (_indexOfTopLevelKeyword(trimmed, 'intersect') >= 0) return null;

    final fromAt = _indexOfTopLevelKeyword(trimmed, 'from');
    if (fromAt < 0) return null;

    var i = fromAt + 4;
    i = _skipTrivia(trimmed, i);
    if (i >= trimmed.length) return null;
    if (trimmed[i] == '(') return null;

    final first = _readIdent(trimmed, i);
    if (first == null) return null;
    i = first.next;

    String? schema;
    String table;
    i = _skipTrivia(trimmed, i);
    if (i < trimmed.length && trimmed[i] == '.') {
      i++;
      i = _skipTrivia(trimmed, i);
      final second = _readIdent(trimmed, i);
      if (second == null) return null;
      schema = first.name;
      table = second.name;
      i = second.next;
    } else {
      table = first.name;
    }

    i = _skipTrivia(trimmed, i);
    if (i < trimmed.length) {
      final asKw = _readBareWord(trimmed, i);
      if (asKw != null && asKw.word.toLowerCase() == 'as') {
        i = _skipTrivia(trimmed, asKw.next);
        final alias = _readIdent(trimmed, i);
        if (alias == null) return null;
        i = alias.next;
      } else if (asKw != null &&
          !_fromFollowers.contains(asKw.word.toLowerCase()) &&
          !_joinStarters.contains(asKw.word.toLowerCase())) {
        i = asKw.next;
      }
    }

    i = _skipTrivia(trimmed, i);
    if (i < trimmed.length && trimmed[i] == ',') return null;

    if (table.isEmpty) return null;
    return SqlTableTarget(tableName: table, schema: schema);
  }
}

bool _startsWithKeyword(String sql, String keyword) {
  final i = _skipTrivia(sql, 0);
  if (i >= sql.length || !_isIdentStart(sql[i])) return false;
  final word = _readBareWord(sql, i);
  return word != null && word.word.toLowerCase() == keyword.toLowerCase();
}

/// Whether SQL-grid Save may run for this result set.
///
/// Requires a simple single-table SELECT, a non-empty primary key, and every
/// PK column present in [resultColumns] (so WHERE can address the row).
bool sqlResultGridSaveEnabled({
  required String? sql,
  required List<String> resultColumns,
  required List<String> primaryKeys,
}) {
  if (sql == null || SqlTableTargetExtractor.extract(sql) == null) {
    return false;
  }
  if (primaryKeys.isEmpty) return false;
  final cols = resultColumns.toSet();
  return primaryKeys.every(cols.contains);
}

int _indexOfTopLevelKeyword(String sql, String keyword) {
  final want = keyword.toLowerCase();
  var i = 0;
  var depth = 0;
  while (i < sql.length) {
    i = _skipTrivia(sql, i);
    if (i >= sql.length) break;
    final c = sql[i];
    if (c == "'" || c == '"' || c == '`') {
      final end = _skipQuoted(sql, i, c);
      if (end < 0) return -1;
      i = end;
      continue;
    }
    if (c == '(') {
      depth++;
      i++;
      continue;
    }
    if (c == ')') {
      if (depth > 0) depth--;
      i++;
      continue;
    }
    if (depth == 0 && _isIdentStart(c)) {
      final start = i;
      i++;
      while (i < sql.length && _isIdentPart(sql[i])) {
        i++;
      }
      if (sql.substring(start, i).toLowerCase() == want) {
        final beforeOk = start == 0 || !_isIdentPart(sql[start - 1]);
        final afterOk = i >= sql.length || !_isIdentPart(sql[i]);
        if (beforeOk && afterOk) return start;
      }
      continue;
    }
    i++;
  }
  return -1;
}

int _skipTrivia(String sql, int i) {
  while (i < sql.length) {
    final c = sql[i];
    if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
      i++;
      continue;
    }
    if (c == '-' && i + 1 < sql.length && sql[i + 1] == '-') {
      i += 2;
      while (i < sql.length && sql[i] != '\n') {
        i++;
      }
      continue;
    }
    if (c == '/' && i + 1 < sql.length && sql[i + 1] == '*') {
      final end = sql.indexOf('*/', i + 2);
      i = end < 0 ? sql.length : end + 2;
      continue;
    }
    break;
  }
  return i;
}

({String name, int next})? _readIdent(String sql, int i) {
  if (i >= sql.length) return null;
  final c = sql[i];
  if (c == '"' || c == '`' || c == '[') {
    final close = c == '[' ? ']' : c;
    final end = _skipQuoted(sql, i, close);
    if (end < 0) return null;
    return (name: sql.substring(i + 1, end - 1), next: end);
  }
  final word = _readBareWord(sql, i);
  if (word == null) return null;
  return (name: word.word, next: word.next);
}

({String word, int next})? _readBareWord(String sql, int i) {
  if (i >= sql.length || !_isIdentStart(sql[i])) return null;
  final start = i;
  i++;
  while (i < sql.length && _isIdentPart(sql[i])) {
    i++;
  }
  return (word: sql.substring(start, i), next: i);
}

int _skipQuoted(String sql, int i, String quote) {
  final open = sql[i];
  i++;
  while (i < sql.length) {
    if (sql[i] == quote) {
      if (quote != ']' && i + 1 < sql.length && sql[i + 1] == quote) {
        i += 2;
        continue;
      }
      return i + 1;
    }
    if (open == '[' && sql[i] == ']') return i + 1;
    i++;
  }
  return -1;
}

bool _isIdentStart(String c) {
  final u = c.codeUnitAt(0);
  return (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95;
}

bool _isIdentPart(String c) {
  final u = c.codeUnitAt(0);
  return _isIdentStart(c) || (u >= 48 && u <= 57);
}
