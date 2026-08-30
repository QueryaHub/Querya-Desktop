/// Categorization of destructive SQL operations that can alter or destroy schema/data.
enum DestructiveSqlType {
  dropDatabase,
  dropSchema,
  dropTable,
  dropView,
  dropMaterializedView,
  truncateTable,
  unconditionalDelete;

  String get label => switch (this) {
        DestructiveSqlType.dropDatabase => 'DROP DATABASE',
        DestructiveSqlType.dropSchema => 'DROP SCHEMA',
        DestructiveSqlType.dropTable => 'DROP TABLE',
        DestructiveSqlType.dropView => 'DROP VIEW',
        DestructiveSqlType.dropMaterializedView => 'DROP MATERIALIZED VIEW',
        DestructiveSqlType.truncateTable => 'TRUNCATE TABLE',
        DestructiveSqlType.unconditionalDelete => 'UNCONDITIONAL DELETE',
      };

  String get riskLevel => switch (this) {
        DestructiveSqlType.dropDatabase => 'CRITICAL',
        DestructiveSqlType.dropSchema => 'HIGH',
        DestructiveSqlType.dropTable => 'HIGH',
        DestructiveSqlType.truncateTable => 'HIGH',
        DestructiveSqlType.unconditionalDelete => 'HIGH',
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
        DestructiveSqlType.dropView =>
          'Drops view "$targetName".',
        DestructiveSqlType.dropMaterializedView =>
          'Drops materialized view "$targetName".',
        DestructiveSqlType.truncateTable =>
          'Quickly deletes all rows from table "$targetName" without transaction rollbacks in some engines.',
        DestructiveSqlType.unconditionalDelete =>
          'Deletes all rows from table "$targetName" (no WHERE clause detected).',
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
    if (operations.any((o) => o.type.riskLevel == 'CRITICAL')) return 'CRITICAL';
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

  /// Strips comments and string literals to prevent false positives when keywords
  /// appear inside strings or comments.
  static String stripCommentsAndStrings(String sql) {
    final buffer = StringBuffer();
    final len = sql.length;
    var i = 0;

    while (i < len) {
      // 1. Line comment: --
      if (i + 1 < len && sql[i] == '-' && sql[i + 1] == '-') {
        i += 2;
        while (i < len && sql[i] != '\n' && sql[i] != '\r') {
          i++;
        }
        buffer.write(' ');
        continue;
      }

      // 2. Block comment: /* ... */
      if (i + 1 < len && sql[i] == '/' && sql[i + 1] == '*') {
        i += 2;
        while (i + 1 < len && !(sql[i] == '*' && sql[i + 1] == '/')) {
          i++;
        }
        if (i + 1 < len) {
          i += 2; // skip */
        } else {
          i = len;
        }
        buffer.write(' ');
        continue;
      }

      // 3. Dollar quotes in PostgreSQL: $$ or $tag$
      if (sql[i] == '\$') {
        final match = RegExp(r'^\$([a-zA-Z0-9_]*)\$').matchAsPrefix(sql.substring(i));
        if (match != null) {
          final tag = match.group(0)!;
          i += tag.length;
          final closeIdx = sql.indexOf(tag, i);
          if (closeIdx != -1) {
            i = closeIdx + tag.length;
          } else {
            i = len;
          }
          buffer.write("''");
          continue;
        }
      }

      // 4. Standard string literal: '...' (supporting '' escaping)
      if (sql[i] == "'") {
        i++;
        while (i < len) {
          if (sql[i] == "'") {
            if (i + 1 < len && sql[i + 1] == "'") {
              i += 2; // escaped quote
            } else {
              i++; // closing quote
              break;
            }
          } else if (sql[i] == '\\' && i + 1 < len) {
            i += 2; // escaped char
          } else {
            i++;
          }
        }
        buffer.write("''");
        continue;
      }

      buffer.write(sql[i]);
      i++;
    }

    return buffer.toString();
  }

  /// Splits an SQL query into individual statements on `;`, taking into account
  /// comments and string literals.
  static List<String> splitStatements(String sql) {
    final statements = <String>[];
    final current = StringBuffer();
    final len = sql.length;
    var i = 0;

    while (i < len) {
      // Line comment
      if (i + 1 < len && sql[i] == '-' && sql[i + 1] == '-') {
        while (i < len && sql[i] != '\n' && sql[i] != '\r') {
          current.write(sql[i]);
          i++;
        }
        continue;
      }

      // Block comment
      if (i + 1 < len && sql[i] == '/' && sql[i + 1] == '*') {
        current.write('/*');
        i += 2;
        while (i + 1 < len && !(sql[i] == '*' && sql[i + 1] == '/')) {
          current.write(sql[i]);
          i++;
        }
        if (i + 1 < len) {
          current.write('*/');
          i += 2;
        } else {
          i = len;
        }
        continue;
      }

      // Dollar quotes
      if (sql[i] == '\$') {
        final match = RegExp(r'^\$([a-zA-Z0-9_]*)\$').matchAsPrefix(sql.substring(i));
        if (match != null) {
          final tag = match.group(0)!;
          current.write(tag);
          i += tag.length;
          final closeIdx = sql.indexOf(tag, i);
          if (closeIdx != -1) {
            current.write(sql.substring(i, closeIdx + tag.length));
            i = closeIdx + tag.length;
          } else {
            current.write(sql.substring(i));
            i = len;
          }
          continue;
        }
      }

      // String literal
      if (sql[i] == "'") {
        current.write("'");
        i++;
        while (i < len) {
          if (sql[i] == "'") {
            current.write("'");
            if (i + 1 < len && sql[i + 1] == "'") {
              current.write("'");
              i += 2;
            } else {
              i++;
              break;
            }
          } else if (sql[i] == '\\' && i + 1 < len) {
            current.write(sql[i]);
            current.write(sql[i + 1]);
            i += 2;
          } else {
            current.write(sql[i]);
            i++;
          }
        }
        continue;
      }

      // Statement delimiter
      if (sql[i] == ';') {
        final stmt = current.toString().trim();
        if (stmt.isNotEmpty) {
          statements.add(stmt);
        }
        current.clear();
        i++;
        continue;
      }

      current.write(sql[i]);
      i++;
    }

    final remaining = current.toString().trim();
    if (remaining.isNotEmpty) {
      statements.add(remaining);
    }

    return statements;
  }

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
        final target = (schema != null && schema.isNotEmpty) ? '$schema.$view' : view;
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
        final target = (schema != null && schema.isNotEmpty) ? '$schema.$view' : view;
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
        final target = (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
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
        final target = (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
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
        final hasWhere = RegExp(r'\bWHERE\b', caseSensitive: false).hasMatch(sanitized);
        if (!hasWhere) {
          final schema = deleteMatch.group(1);
          final table = deleteMatch.group(2) ?? 'table';
          final target = (schema != null && schema.isNotEmpty) ? '$schema.$table' : table;
          operations.add(
            DestructiveSqlOperation(
              type: DestructiveSqlType.unconditionalDelete,
              targetName: target,
              rawStatement: rawStmt.trim(),
            ),
          );
        }
      }
    }

    return DestructiveSqlInspectionResult(operations: operations);
  }
}
