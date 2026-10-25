import 'package:querya_desktop/core/database/sql_lexical_scanner.dart';
import 'package:querya_desktop/core/database/sql_statement_splitter.dart';

/// Categorization of destructive SQL / Mongo / Redis operations that can
/// alter or destroy schema/data.
enum DestructiveSqlType {
  dropDatabase,
  dropSchema,
  dropTable,
  dropView,
  dropMaterializedView,
  dropColumn,
  dropOther,
  truncateTable,
  unconditionalDelete,
  unconditionalUpdate,
  dropCollection,
  deleteDocument,
  redisDel,
  redisHdel,
  redisSrem,
  redisZrem,
  redisRename,
  redisLrem,
  redisFlushAll,
  redisFlushDb,
  redisShutdown,
  redisKeys;

  String get label => switch (this) {
        DestructiveSqlType.dropDatabase => 'DROP DATABASE',
        DestructiveSqlType.dropSchema => 'DROP SCHEMA',
        DestructiveSqlType.dropTable => 'DROP TABLE',
        DestructiveSqlType.dropView => 'DROP VIEW',
        DestructiveSqlType.dropMaterializedView => 'DROP MATERIALIZED VIEW',
        DestructiveSqlType.dropColumn => 'DROP COLUMN',
        DestructiveSqlType.dropOther => 'DROP',
        DestructiveSqlType.truncateTable => 'TRUNCATE TABLE',
        DestructiveSqlType.unconditionalDelete => 'UNCONDITIONAL DELETE',
        DestructiveSqlType.unconditionalUpdate => 'UNCONDITIONAL UPDATE',
        DestructiveSqlType.dropCollection => 'DROP COLLECTION',
        DestructiveSqlType.deleteDocument => 'DELETE DOCUMENT',
        DestructiveSqlType.redisDel => 'DEL',
        DestructiveSqlType.redisHdel => 'HDEL',
        DestructiveSqlType.redisSrem => 'SREM',
        DestructiveSqlType.redisZrem => 'ZREM',
        DestructiveSqlType.redisRename => 'RENAME',
        DestructiveSqlType.redisLrem => 'LREM',
        DestructiveSqlType.redisFlushAll => 'FLUSHALL',
        DestructiveSqlType.redisFlushDb => 'FLUSHDB',
        DestructiveSqlType.redisShutdown => 'SHUTDOWN',
        DestructiveSqlType.redisKeys => 'KEYS *',
      };

  String get riskLevel => switch (this) {
        DestructiveSqlType.dropDatabase => 'CRITICAL',
        DestructiveSqlType.dropSchema => 'HIGH',
        DestructiveSqlType.dropTable => 'HIGH',
        DestructiveSqlType.truncateTable => 'HIGH',
        DestructiveSqlType.unconditionalDelete => 'HIGH',
        DestructiveSqlType.unconditionalUpdate => 'HIGH',
        DestructiveSqlType.dropCollection => 'HIGH',
        DestructiveSqlType.deleteDocument => 'HIGH',
        DestructiveSqlType.redisDel => 'HIGH',
        DestructiveSqlType.redisHdel => 'HIGH',
        DestructiveSqlType.redisSrem => 'HIGH',
        DestructiveSqlType.redisZrem => 'HIGH',
        DestructiveSqlType.redisRename => 'HIGH',
        DestructiveSqlType.redisLrem => 'HIGH',
        DestructiveSqlType.redisFlushAll => 'CRITICAL',
        DestructiveSqlType.redisFlushDb => 'CRITICAL',
        DestructiveSqlType.redisShutdown => 'CRITICAL',
        DestructiveSqlType.redisKeys => 'HIGH',
        DestructiveSqlType.dropColumn => 'HIGH',
        DestructiveSqlType.dropOther => 'MEDIUM',
        DestructiveSqlType.dropMaterializedView => 'MEDIUM',
        DestructiveSqlType.dropView => 'MEDIUM',
      };
}

/// Represents a single detected destructive operation within an SQL script.
class DestructiveSqlOperation {
  const DestructiveSqlOperation({
    required this.type,
    required this.targetName,
    required this.rawStatement,
  });

  final DestructiveSqlType type;
  final String targetName;
  final String rawStatement;

  String get description => switch (type) {
        DestructiveSqlType.dropDatabase =>
          'Permanently drops database "$targetName" and all contained schemas, tables, and records.',
        DestructiveSqlType.dropSchema =>
          'Permanently drops schema "$targetName" and all contained tables.',
        DestructiveSqlType.dropTable =>
          'Permanently drops table structure and all data in "$targetName".',
        DestructiveSqlType.dropView => 'Drops view "$targetName".',
        DestructiveSqlType.dropMaterializedView =>
          'Drops materialized view "$targetName".',
        DestructiveSqlType.dropColumn =>
          'Permanently drops a column of "$targetName" and the data in it.',
        DestructiveSqlType.dropOther =>
          'Permanently drops "$targetName". Objects that depend on it may be lost too.',
        DestructiveSqlType.truncateTable =>
          'Quickly deletes all rows from table "$targetName" without transaction rollbacks in some engines.',
        DestructiveSqlType.unconditionalDelete =>
          'Deletes all rows from table "$targetName" (no WHERE clause detected).',
        DestructiveSqlType.unconditionalUpdate =>
          'Modifies all rows in table "$targetName" (no WHERE clause detected).',
        DestructiveSqlType.dropCollection =>
          'Permanently drops collection "$targetName" and all documents in it.',
        DestructiveSqlType.deleteDocument =>
          'Permanently deletes document "$targetName". This cannot be undone.',
        DestructiveSqlType.redisDel =>
          'Permanently deletes Redis key "$targetName". This cannot be undone.',
        DestructiveSqlType.redisHdel =>
          'Permanently removes hash field "$targetName".',
        DestructiveSqlType.redisSrem =>
          'Permanently removes set member "$targetName".',
        DestructiveSqlType.redisZrem =>
          'Permanently removes sorted-set member "$targetName".',
        DestructiveSqlType.redisRename =>
          'Renaming will overwrite existing key "$targetName". The existing value will be permanently lost.',
        DestructiveSqlType.redisLrem =>
          'Permanently removes list element "$targetName".',
        DestructiveSqlType.redisFlushAll =>
          'Permanently deletes all keys across all Redis databases! This cannot be undone.',
        DestructiveSqlType.redisFlushDb =>
          'Permanently deletes all keys in the current Redis database ($targetName).',
        DestructiveSqlType.redisShutdown =>
          'Shuts down the Redis server instance. All clients will be disconnected.',
        DestructiveSqlType.redisKeys =>
          'Scanning all keys with "KEYS $targetName" can block Redis on large production instances. Consider SCAN instead.',
      };
}

/// Result of inspecting SQL text for destructive operations.
class DestructiveSqlInspectionResult {
  const DestructiveSqlInspectionResult({
    required this.operations,
  });

  final List<DestructiveSqlOperation> operations;

  bool get isDestructive => operations.isNotEmpty;

  /// Returns highest risk level present ('CRITICAL', 'HIGH', 'MEDIUM', or 'NONE').
  String get maxRiskLevel {
    if (operations.isEmpty) return 'NONE';
    if (operations.any((o) => o.type.riskLevel == 'CRITICAL')) {
      return 'CRITICAL';
    }
    if (operations.any((o) => o.type.riskLevel == 'HIGH')) return 'HIGH';
    return 'MEDIUM';
  }
}

/// Heuristic analyzer and sanitizer for detecting destructive SQL queries
/// before executing them in the SQL workspace.
abstract final class DestructiveSqlDetector {
  /// One identifier part, optionally quoted: letters and digits of any script
  /// (`заказы`), `_` and `$`.
  static const _id = r'["`]?([\p{L}\p{N}_$]+)["`]?';

  static String _withId(String pattern) => pattern.replaceAll('{id}', _id);

  static final _dropDatabaseRegex = RegExp(
    _withId(r'^\s*DROP\s+DATABASE\s+(?:IF\s+EXISTS\s+)?(?:{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropSchemaRegex = RegExp(
    _withId(r'^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?(?:{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropTableRegex = RegExp(
    _withId(r'^\s*DROP\s+(?:TEMPORARY\s+|FOREIGN\s+)?TABLE\s+(?:IF\s+EXISTS\s+)?(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropMatViewRegex = RegExp(
    _withId(r'^\s*DROP\s+MATERIALIZED\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropViewRegex = RegExp(
    _withId(r'^\s*DROP\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _truncateRegex = RegExp(
    _withId(r'^\s*TRUNCATE\s+(?:TABLE\s+)?(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _deleteRegex = RegExp(
    _withId(r'^\s*DELETE\s+(?:[^;]*?\s)??FROM\s+(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _updateRegex = RegExp(
    _withId(r'^\s*UPDATE\s+(?:(?:LOW_PRIORITY|IGNORE|ONLY)\s+)*(?:(?:{id}\.)?{id})'),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropOtherRegex = RegExp(
    _withId(
      r'^\s*DROP\s+(?:UNIQUE\s+)?(?:INDEX|TYPE|FUNCTION|PROCEDURE|ROLE|USER|TRIGGER|EVENT\s+TRIGGER|SEQUENCE|DOMAIN|EXTENSION|TABLESPACE|PUBLICATION|SUBSCRIPTION|AGGREGATE|POLICY|RULE|SERVER|OWNED\s+BY)\s+(?:CONCURRENTLY\s+)?(?:IF\s+EXISTS\s+)?(?:(?:{id}\.)?{id})',
    ),
    caseSensitive: false,
    unicode: true,
  );

  static final _dropColumnRegex = RegExp(
    _withId(
      r'^\s*ALTER\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:ONLY\s+)?(?:(?:{id}\.)?{id})[^;]*?\bDROP\s+(?:COLUMN\b|(?!(?:CONSTRAINT|INDEX|KEY|PRIMARY|FOREIGN|CHECK|DEFAULT|NOT|IDENTITY|EXPRESSION|PARTITION|IF|TRIGGER|RULE|PERIOD)\b)[\p{L}"`_])',
    ),
    caseSensitive: false,
    unicode: true,
  );

  /// `EXPLAIN ANALYZE` runs the statement it explains.
  static final _explainAnalyzeRegex = RegExp(
    r'^\s*EXPLAIN\s+(?:\([^)]*\bANALY[SZ]E\b[^)]*\)|ANALY[SZ]E\b(?:\s+VERBOSE\b)?)\s*',
    caseSensitive: false,
  );

  static final _withRegex =
      RegExp(r'^\s*WITH\s+(?:RECURSIVE\s+)?', caseSensitive: false);

  /// The keyword that starts the main statement after a `WITH` list.
  static final _mainStartRegex = RegExp(
    r'^(?:SELECT|INSERT|UPDATE|DELETE|MERGE|VALUES|TABLE)\b',
    caseSensitive: false,
  );

  /// Splits [sanitized] (after an `EXPLAIN ANALYZE` prefix) into the bodies of
  /// its `WITH name AS (...)` list and the main statement that follows it. A
  /// statement without `WITH` is its own main statement.
  static ({List<String> bodies, String main}) _splitWith(String sanitized) {
    var sql = sanitized;
    final explain = _explainAnalyzeRegex.firstMatch(sql);
    if (explain != null) sql = sql.substring(explain.end);
    final withMatch = _withRegex.firstMatch(sql);
    if (withMatch == null) return (bodies: const [], main: sql);
    final bodies = <String>[];
    var depth = 0;
    var bodyStart = 0;
    for (var i = withMatch.end; i < sql.length; i++) {
      final ch = sql[i];
      if (ch == '(') {
        if (depth == 0) bodyStart = i + 1;
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
        if (depth == 0) bodies.add(sql.substring(bodyStart, i));
      } else if (depth == 0 &&
          !RegExp(r'[\w$]').hasMatch(sql[i - 1]) &&
          _mainStartRegex.hasMatch(sql.substring(i))) {
        return (bodies: bodies, main: sql.substring(i));
      }
    }
    return (bodies: bodies, main: sql);
  }

  /// An unconditional `DELETE` / `UPDATE` in [sql], or null.
  static DestructiveSqlOperation? _unconditionalDml(
    String sql,
    String rawStatement,
  ) {
    String targetOf(RegExpMatch m) {
      final schema = m.group(1);
      final table = m.group(2) ?? 'table';
      return (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
    }

    final deleteMatch = _deleteRegex.firstMatch(sql);
    if (deleteMatch != null) {
      if (_hasTopLevelWhere(sql)) return null;
      return DestructiveSqlOperation(
        type: DestructiveSqlType.unconditionalDelete,
        targetName: targetOf(deleteMatch),
        rawStatement: rawStatement,
      );
    }
    final updateMatch = _updateRegex.firstMatch(sql);
    if (updateMatch != null &&
        _setRegex.hasMatch(sql) &&
        !_hasTopLevelWhere(sql)) {
      return DestructiveSqlOperation(
        type: DestructiveSqlType.unconditionalUpdate,
        targetName: targetOf(updateMatch),
        rawStatement: rawStatement,
      );
    }
    return null;
  }

  static final _whereRegex = RegExp(r'\bWHERE\b', caseSensitive: false);
  static final _setRegex = RegExp(r'\bSET\b', caseSensitive: false);

  /// True when [sanitized] has a WHERE outside any parentheses, so a WHERE
  /// inside a subquery (`SET x = (SELECT ... WHERE ...)`) does not count.
  static bool _hasTopLevelWhere(String sanitized) {
    final top = StringBuffer();
    var depth = 0;
    for (var i = 0; i < sanitized.length; i++) {
      final ch = sanitized[i];
      if (ch == '(') {
        depth++;
      } else if (ch == ')') {
        if (depth > 0) depth--;
      } else if (depth == 0) {
        top.write(ch);
      }
    }
    return _whereRegex.hasMatch(top.toString());
  }

  static const int _chLf = 0x0A;
  static const int _chCr = 0x0D;
  static const int _chQuote = 0x27; // '
  static const int _chDollar = 0x24; // $
  static const int _chStar = 0x2A; // *
  static const int _chSlash = 0x2F; // /
  static const int _chDash = 0x2D; // -
  static const int _chBackslash = 0x5C; // \

  static bool _isTagChar(int c) =>
      (c >= 0x30 && c <= 0x39) || // 0-9
      (c >= 0x41 && c <= 0x5A) || // A-Z
      (c >= 0x61 && c <= 0x7A) || // a-z
      c == 0x5F; // _

  /// Offset of the end of the line comment whose body starts at [start]: the
  /// line break itself is not consumed.
  static int _skipLineComment(String sql, int start, int len) {
    var i = start;
    while (i < len) {
      final c = sql.codeUnitAt(i);
      if (c == _chLf || c == _chCr) break;
      i++;
    }
    return i;
  }

  /// Offset after the `*/` that closes the block comment whose body starts at
  /// [start]; [len] when it is never closed.
  static int _skipBlockComment(String sql, int start, int len) {
    var i = start;
    while (i + 1 < len) {
      if (sql.codeUnitAt(i) == _chStar && sql.codeUnitAt(i + 1) == _chSlash) {
        return i + 2;
      }
      i++;
    }
    return len;
  }

  /// Offset after the dollar-quoted string (`$$...$$`, `$tag$...$tag$`) that
  /// opens at [start], [len] when it is never closed, or [start] when there is
  /// no opening tag at [start] (`$1`, a lone `$`).
  static int _skipDollarQuote(String sql, int start, int len) {
    var j = start + 1;
    while (j < len && _isTagChar(sql.codeUnitAt(j))) {
      j++;
    }
    if (j >= len || sql.codeUnitAt(j) != _chDollar) return start;
    final bodyStart = j + 1;
    final close = sql.indexOf(sql.substring(start, bodyStart), bodyStart);
    return close == -1 ? len : close + (bodyStart - start);
  }

  /// Offset after the single-quoted literal whose body starts at [start]
  /// (`''` and backslash escapes); [len] when it is never closed.
  static int _skipStringLiteral(
    String sql,
    int start,
    int len, {
    required bool backslashEscapes,
  }) {
    var i = start;
    while (i < len) {
      final c = sql.codeUnitAt(i);
      if (c == _chQuote) {
        if (i + 1 < len && sql.codeUnitAt(i + 1) == _chQuote) {
          i += 2; // escaped quote
        } else {
          return i + 1; // closing quote
        }
      } else if (backslashEscapes && c == _chBackslash && i + 1 < len) {
        i += 2; // escaped char
      } else {
        i++;
      }
    }
    return len;
  }

  /// Strips comments and string literals to prevent false positives when keywords
  /// appear inside strings or comments.
  ///
  /// Scans code units with the `_skip*` helpers (no per-character strings, no
  /// regex, no copy of the rest of the script at every `$`), and appends the
  /// text between tokens in runs (#1511).
  ///
  /// [backslashEscapes] is whether `\'` escapes a quote (MySQL; the default).
  /// With `false` (PostgreSQL, SQLite) a backslash is an ordinary character,
  /// except inside an `E'...'` string, as the server reads it.
  static String stripCommentsAndStrings(
    String sql, {
    bool backslashEscapes = true,
  }) {
    final buffer = StringBuffer();
    final len = sql.length;
    var i = 0;
    var runStart = 0;

    void flushRun(int end) {
      if (end > runStart) buffer.write(sql.substring(runStart, end));
    }

    while (i < len) {
      final c = sql.codeUnitAt(i);
      final next = i + 1 < len ? sql.codeUnitAt(i + 1) : -1;
      int after;
      String? replacement;

      if (c == _chDash && next == _chDash) {
        after = _skipLineComment(sql, i + 2, len);
        replacement = ' ';
      } else if (c == _chSlash && next == _chStar) {
        after = _skipBlockComment(sql, i + 2, len);
        replacement = ' ';
      } else if (c == _chDollar) {
        after = _skipDollarQuote(sql, i, len);
        if (after == i) {
          i++;
          continue;
        }
        replacement = "''";
      } else if (c == _chQuote) {
        after = _skipStringLiteral(
          sql,
          i + 1,
          len,
          backslashEscapes:
              backslashEscapes || SqlLexicalScanner.isEscapeStringPrefix(sql, i),
        );
        replacement = "''";
      } else {
        i++;
        continue;
      }

      flushRun(i);
      buffer.write(replacement);
      i = after;
      runStart = i;
    }
    flushRun(len);

    return buffer.toString();
  }

  /// Splits an SQL query into individual statements on `;`, taking into account
  /// comments and string literals.
  ///
  /// [backslashEscapes]: see [stripCommentsAndStrings].
  static List<String> splitStatements(
    String sql, {
    bool backslashEscapes = true,
  }) =>
      [
        for (final span
            in SqlStatementSplitter.spans(sql, backslashEscapes: backslashEscapes))
          span.textIn(sql),
      ];

  /// Inspects [sql] and returns any detected destructive operations.
  ///
  /// [backslashEscapes]: see [stripCommentsAndStrings].
  static DestructiveSqlInspectionResult inspect(
    String sql, {
    bool backslashEscapes = true,
  }) {
    final statements = splitStatements(sql, backslashEscapes: backslashEscapes);
    final operations = <DestructiveSqlOperation>[];

    for (final rawStmt in statements) {
      final sanitized = stripCommentsAndStrings(
        rawStmt,
        backslashEscapes: backslashEscapes,
      ).trim();
      if (sanitized.isEmpty) continue;
      final withParts = _splitWith(sanitized);
      final effective = withParts.main;

      // 1. DROP DATABASE
      final dropDbMatch = _dropDatabaseRegex.firstMatch(sanitized);
      if (dropDbMatch != null) {
        final target = dropDbMatch.group(1) ?? 'database';
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropDatabase,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 2. DROP SCHEMA
      final dropSchemaMatch = _dropSchemaRegex.firstMatch(sanitized);
      if (dropSchemaMatch != null) {
        final target = dropSchemaMatch.group(1) ?? 'schema';
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropSchema,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 3. DROP MATERIALIZED VIEW
      final dropMatViewMatch = _dropMatViewRegex.firstMatch(sanitized);
      if (dropMatViewMatch != null) {
        final schema = dropMatViewMatch.group(1);
        final view = dropMatViewMatch.group(2) ?? 'view';
        final target =
            (schema != null && schema.isNotEmpty) ? '$schema.$view' : view;
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropMaterializedView,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 4. DROP VIEW
      final dropViewMatch = _dropViewRegex.firstMatch(sanitized);
      if (dropViewMatch != null) {
        final schema = dropViewMatch.group(1);
        final view = dropViewMatch.group(2) ?? 'view';
        final target =
            (schema != null && schema.isNotEmpty) ? '$schema.$view' : view;
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropView,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 5. DROP TABLE
      final dropTableMatch = _dropTableRegex.firstMatch(sanitized);
      if (dropTableMatch != null) {
        final schema = dropTableMatch.group(1);
        final table = dropTableMatch.group(2) ?? 'table';
        final target =
            (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropTable,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 5b. DROP INDEX / TYPE / FUNCTION / ROLE / USER ...
      final dropOtherMatch = _dropOtherRegex.firstMatch(sanitized);
      if (dropOtherMatch != null) {
        final schema = dropOtherMatch.group(1);
        final name = dropOtherMatch.group(2) ?? 'object';
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropOther,
            targetName:
                (schema != null && schema.isNotEmpty) ? '$schema.$name' : name,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 5c. ALTER TABLE ... DROP COLUMN
      final dropColumnMatch = _dropColumnRegex.firstMatch(sanitized);
      if (dropColumnMatch != null) {
        final schema = dropColumnMatch.group(1);
        final table = dropColumnMatch.group(2) ?? 'table';
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.dropColumn,
            targetName:
                (schema != null && schema.isNotEmpty) ? '$schema.$table' : table,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 6. TRUNCATE
      final truncateMatch = _truncateRegex.firstMatch(sanitized);
      if (truncateMatch != null) {
        final schema = truncateMatch.group(1);
        final table = truncateMatch.group(2) ?? 'table';
        final target =
            (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.truncateTable,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
        continue;
      }

      // 7. DELETE / UPDATE without WHERE: the main statement, and a
      // data-modifying CTE (`WITH d AS (DELETE FROM t RETURNING *) SELECT ...`).
      for (final body in [effective, ...withParts.bodies]) {
        final op = _unconditionalDml(body.trim(), rawStmt.trim());
        if (op != null) operations.add(op);
      }
    }

    return DestructiveSqlInspectionResult(operations: operations);
  }
}
