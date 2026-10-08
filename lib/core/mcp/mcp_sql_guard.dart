import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/sql_mutation_classifier.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Decides whether SQL sent by an MCP client may run.
///
/// First of three read-only layers (the others are the read-only database
/// session and the per-connection access policy). Conservative on purpose:
/// anything it cannot prove harmless is refused with a message the model can
/// act on.
abstract final class McpSqlGuard {
  static const _readStarts = {
    'SELECT',
    'WITH',
    'EXPLAIN',
    'SHOW',
    'DESCRIBE',
    'DESC',
    'VALUES',
  };

  static final _firstWord = RegExp(r'^\(*\s*([A-Z_]+)');

  /// `SELECT ... INTO` creates a table (Postgres) or writes a file (MySQL
  /// `INTO OUTFILE`); row locks have no place in read-only exploration.
  static final _selectSideEffects = RegExp(
    r'\bINTO\b|\bFOR\s+(UPDATE|SHARE|NO\s+KEY\s+UPDATE|KEY\s+SHARE)\b|\bLOCK\s+IN\s+SHARE\s+MODE\b',
  );

  /// `EXPLAIN ANALYZE` executes the statement; the rest would explain a write.
  static final _explainForbidden = RegExp(
    r'\b(ANALYZE|ANALYSE|INSERT|UPDATE|DELETE|MERGE|REPLACE|CREATE|DROP|ALTER|TRUNCATE|GRANT|REVOKE|CALL|DO|COPY)\b',
  );

  /// Functions that act on the server even inside a read-only transaction.
  static final _forbiddenFunctions = RegExp(
    r'\b(PG_TERMINATE_BACKEND|PG_CANCEL_BACKEND|PG_RELOAD_CONF|PG_ROTATE_LOGFILE|'
    r'PG_READ_FILE|PG_READ_BINARY_FILE|PG_LS_DIR|PG_STAT_FILE|LO_IMPORT|LO_EXPORT|'
    r'DBLINK\w*|SET_CONFIG|LOAD_FILE|LOAD_EXTENSION|WRITEFILE|READFILE|FSDIR)\s*\(',
  );

  /// SQLite pragmas that only read the schema.
  static const _readPragmas = {
    'TABLE_INFO',
    'TABLE_XINFO',
    'TABLE_LIST',
    'INDEX_LIST',
    'INDEX_INFO',
    'INDEX_XINFO',
    'FOREIGN_KEY_LIST',
    'DATABASE_LIST',
    'COLLATION_LIST',
  };

  static final _pragma =
      RegExp(r'^PRAGMA\s+(?:[A-Z_]+\.)?([A-Z_]+)\s*(\(\s*[A-Z_0-9]*\s*\))?$');

  /// Returns `null` when [sql] may run, or the reason it may not.
  static String? check(String sql, SqlDialect dialect) {
    final statements = DestructiveSqlDetector.splitStatements(sql)
        .where((s) => DestructiveSqlDetector.stripCommentsAndStrings(s)
            .trim()
            .isNotEmpty)
        .toList();
    if (statements.isEmpty) return 'The query is empty.';
    if (statements.length > 1) {
      return 'Only one statement per call is allowed; send them separately.';
    }
    final statement = statements.single;
    final upper = DestructiveSqlDetector.stripCommentsAndStrings(statement)
        .trim()
        .replaceAll(RegExp(r';\s*$'), '')
        .toUpperCase();
    final first = _firstWord.firstMatch(upper)?.group(1);

    if (first == 'PRAGMA' && dialect == SqlDialect.sqlite) {
      final m = _pragma.firstMatch(upper.replaceAll(RegExp(r'\s+'), ' '));
      if (m != null && _readPragmas.contains(m.group(1))) return null;
      return 'Only schema pragmas are allowed (${_readPragmas.map((p) => p.toLowerCase()).join(', ')}).';
    }
    if (first == null || !_readStarts.contains(first)) {
      return 'Only read-only queries are allowed (SELECT, WITH, EXPLAIN, SHOW, DESCRIBE).';
    }
    if (_forbiddenFunctions.hasMatch(upper)) {
      return 'This query calls a server function that is not allowed over MCP.';
    }
    if (first == 'EXPLAIN') {
      if (_explainForbidden.hasMatch(upper)) {
        return 'EXPLAIN is allowed only for read-only statements and without ANALYZE.';
      }
      return null;
    }
    if (isMutatingSqlStatement(statement)) {
      return 'Data-modifying statements are not allowed over MCP.';
    }
    if (_selectSideEffects.hasMatch(upper)) {
      return 'SELECT ... INTO and row locks (FOR UPDATE / FOR SHARE) are not allowed.';
    }
    return null;
  }
}
