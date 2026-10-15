import 'package:querya_desktop/core/database/sql_statement_splitter.dart';

/// Categorization of destructive SQL / Mongo / Redis operations that can
/// alter or destroy schema/data.
enum DestructiveSqlType {
  dropDatabase,
  dropSchema,
  dropTable,
  dropView,
  dropMaterializedView,
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
  static final _dropDatabaseRegex = RegExp(
    r'^\s*DROP\s+DATABASE\s+(?:IF\s+EXISTS\s+)?(?:["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _dropSchemaRegex = RegExp(
    r'^\s*DROP\s+SCHEMA\s+(?:IF\s+EXISTS\s+)?(?:["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _dropTableRegex = RegExp(
    r'^\s*DROP\s+TABLE\s+(?:IF\s+EXISTS\s+)?(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _dropMatViewRegex = RegExp(
    r'^\s*DROP\s+MATERIALIZED\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _dropViewRegex = RegExp(
    r'^\s*DROP\s+VIEW\s+(?:IF\s+EXISTS\s+)?(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _truncateRegex = RegExp(
    r'^\s*TRUNCATE\s+(?:TABLE\s+)?(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _deleteRegex = RegExp(
    r'^\s*DELETE\s+FROM\s+(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

  static final _updateRegex = RegExp(
    r'^\s*UPDATE\s+(?:(?:LOW_PRIORITY|IGNORE|ONLY)\s+)*(?:(?:["`]?([a-zA-Z0-9_]+)["`]?\.)?["`]?([a-zA-Z0-9_]+)["`]?)',
    caseSensitive: false,
  );

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
  static int _skipStringLiteral(String sql, int start, int len) {
    var i = start;
    while (i < len) {
      final c = sql.codeUnitAt(i);
      if (c == _chQuote) {
        if (i + 1 < len && sql.codeUnitAt(i + 1) == _chQuote) {
          i += 2; // escaped quote
        } else {
          return i + 1; // closing quote
        }
      } else if (c == _chBackslash && i + 1 < len) {
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
  static String stripCommentsAndStrings(String sql) {
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
        after = _skipStringLiteral(sql, i + 1, len);
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
  static List<String> splitStatements(String sql) => [
        for (final span in SqlStatementSplitter.spans(sql)) span.textIn(sql),
      ];

  /// Inspects [sql] and returns any detected destructive operations.
  static DestructiveSqlInspectionResult inspect(String sql) {
    final statements = splitStatements(sql);
    final operations = <DestructiveSqlOperation>[];

    for (final rawStmt in statements) {
      final sanitized = stripCommentsAndStrings(rawStmt).trim();
      if (sanitized.isEmpty) continue;

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

      // 7. DELETE FROM table without WHERE
      final deleteMatch = _deleteRegex.firstMatch(sanitized);
      if (deleteMatch != null) {
        if (!_hasTopLevelWhere(sanitized)) {
          final schema = deleteMatch.group(1);
          final table = deleteMatch.group(2) ?? 'table';
          final target =
              (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
          operations.add(
            DestructiveSqlOperation(
              type: DestructiveSqlType.unconditionalDelete,
              targetName: target,
              rawStatement: rawStmt.trim(),
            ),
          );
        }
        continue;
      }

      // 8. UPDATE table SET ... without WHERE
      final updateMatch = _updateRegex.firstMatch(sanitized);
      if (updateMatch != null &&
          _setRegex.hasMatch(sanitized) &&
          !_hasTopLevelWhere(sanitized)) {
        final schema = updateMatch.group(1);
        final table = updateMatch.group(2) ?? 'table';
        final target =
            (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
        operations.add(
          DestructiveSqlOperation(
            type: DestructiveSqlType.unconditionalUpdate,
            targetName: target,
            rawStatement: rawStmt.trim(),
          ),
        );
      }
    }

    return DestructiveSqlInspectionResult(operations: operations);
  }
}
