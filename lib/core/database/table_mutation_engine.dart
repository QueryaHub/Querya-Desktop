/// Supported SQL dialects for DML mutation generation.
enum SqlDialect {
  postgres,
  mysql,
  sqlite,
}

/// Type of DML mutation.
enum MutationType {
  insert,
  update,
  delete,
}

/// A single generated DML statement.
class TableMutationStatement {
  const TableMutationStatement({
    required this.type,
    required this.sql,
    required this.description,
  });

  final MutationType type;
  final String sql;
  final String description;
}

/// A complete mutation plan containing atomic statements wrapped in a transaction.
class TableMutationPlan {
  const TableMutationPlan({
    required this.dialect,
    required this.tableName,
    this.schema,
    required this.statements,
  });

  final SqlDialect dialect;
  final String tableName;
  final String? schema;
  final List<TableMutationStatement> statements;

  bool get isEmpty => statements.isEmpty;
  int get statementCount => statements.length;

  /// Returns the complete atomic transaction script.
  String toTransactionSql() {
    if (isEmpty) return '';

    final buffer = StringBuffer();
    switch (dialect) {
      case SqlDialect.postgres:
        buffer.writeln('BEGIN;');
      case SqlDialect.mysql:
        buffer.writeln('START TRANSACTION;');
      case SqlDialect.sqlite:
        buffer.writeln('BEGIN TRANSACTION;');
    }

    for (final stmt in statements) {
      buffer.writeln('${stmt.sql};');
    }

    buffer.writeln('COMMIT;');
    return buffer.toString();
  }
}

/// Atomic DML mutation generator for PostgreSQL, MySQL, and SQLite.
abstract final class TableMutationEngine {
  /// Quotes an SQL identifier according to the target [dialect].
  static String quoteIdentifier(String identifier, SqlDialect dialect) {
    switch (dialect) {
      case SqlDialect.mysql:
        return '`${identifier.replaceAll('`', '``')}`';
      case SqlDialect.postgres:
      case SqlDialect.sqlite:
        return '"${identifier.replaceAll('"', '""')}"';
    }
  }

  /// Quotes a qualified table name (e.g. `"public"."users"`).
  static String quoteQualifiedTable(
    String table, {
    String? schema,
    required SqlDialect dialect,
  }) {
    final quotedTable = quoteIdentifier(table, dialect);
    if (schema != null && schema.isNotEmpty && dialect != SqlDialect.sqlite) {
      final quotedSchema = quoteIdentifier(schema, dialect);
      return '$quotedSchema.$quotedTable';
    }
    return quotedTable;
  }

  static bool _isTextType(String dataTypeName) {
    final lower = dataTypeName.toLowerCase().trim();
    return lower.contains('char') ||
        lower.contains('text') ||
        lower.contains('varchar') ||
        lower.contains('string') ||
        lower.contains('uuid') ||
        lower.contains('json') ||
        lower.contains('xml') ||
        lower.contains('clob') ||
        lower.contains('enum') ||
        lower.contains('citext') ||
        lower.contains('name') ||
        lower.contains('bpchar');
  }

  static bool _isBoolType(String dataTypeName) {
    final lower = dataTypeName.toLowerCase().trim();
    return lower == 'bool' ||
        lower == 'boolean' ||
        lower.startsWith('tinyint(1)');
  }

  static bool _isNumericType(String dataTypeName) {
    final lower = dataTypeName.toLowerCase().trim();
    return lower.contains('int') ||
        lower.contains('float') ||
        lower.contains('double') ||
        lower.contains('decimal') ||
        lower.contains('numeric') ||
        lower.contains('real') ||
        lower.contains('serial') ||
        lower.contains('number');
  }

  /// Formats a cell string value safely as an SQL literal or `NULL`.
  /// If [dataTypeName] is provided, formats according to the column type semantics.
  static String formatLiteral(
    String value,
    SqlDialect dialect, {
    String? dataTypeName,
  }) {
    if (value == 'NULL' || value == 'null') {
      return 'NULL';
    }

    final trimmed = value.trim();

    if (dataTypeName != null && dataTypeName.isNotEmpty) {
      if (_isTextType(dataTypeName)) {
        final escaped = value.replaceAll("'", "''");
        return "'$escaped'";
      }

      if (_isBoolType(dataTypeName)) {
        if (trimmed.toLowerCase() == 'true' || trimmed == '1') {
          return dialect == SqlDialect.sqlite ? '1' : 'TRUE';
        }
        if (trimmed.toLowerCase() == 'false' || trimmed == '0') {
          return dialect == SqlDialect.sqlite ? '0' : 'FALSE';
        }
      }

      if (_isNumericType(dataTypeName)) {
        if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) {
          return trimmed;
        }
      }
    }

    // Fallback heuristic:
    // Leading zeros with more digits (e.g. '01234', '007') are preserved as strings
    if (RegExp(r'^0\d+$').hasMatch(trimmed)) {
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }

    // Number literals (integer or floating point, e.g. '123', '0', '0.45', '-5.2')
    if (RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) {
      return trimmed;
    }

    // Boolean literals
    if (trimmed.toLowerCase() == 'true') {
      return dialect == SqlDialect.sqlite ? '1' : 'TRUE';
    }
    if (trimmed.toLowerCase() == 'false') {
      return dialect == SqlDialect.sqlite ? '0' : 'FALSE';
    }

    // String literal with single quote escape
    final escaped = value.replaceAll("'", "''");
    return "'$escaped'";
  }

  /// Generates a [TableMutationPlan] from in-memory staged changes.
  static TableMutationPlan generatePlan({
    required SqlDialect dialect,
    required String tableName,
    String? schema,
    required List<String> columns,
    required List<String> primaryKeys,
    required List<List<String>> originalRows,
    required Map<int, Map<int, String>> modifiedCells,
    required List<List<String>> insertedRows,
    required Set<int> deletedRowIndices,
    Map<String, String>? columnDataTypes,
  }) {
    final statements = <TableMutationStatement>[];
    final tableRef = quoteQualifiedTable(
      tableName,
      schema: schema,
      dialect: dialect,
    );

    // 1. Generate UPDATE statements for modified cells
    for (final entry in modifiedCells.entries) {
      final rowIndex = entry.key;
      final rowModifications = entry.value;

      // Skip if this original row was deleted
      if (deletedRowIndices.contains(rowIndex)) continue;
      if (rowIndex >= originalRows.length) continue;

      final origRow = originalRows[rowIndex];
      final setClauses = <String>[];

      for (final mod in rowModifications.entries) {
        final colIndex = mod.key;
        final stagedVal = mod.value;
        if (colIndex < columns.length) {
          final colName = columns[colIndex];
          final quotedCol = quoteIdentifier(colName, dialect);
          final colType = columnDataTypes?[colName];
          final literal = formatLiteral(stagedVal, dialect, dataTypeName: colType);
          setClauses.add('$quotedCol = $literal');
        }
      }

      if (setClauses.isNotEmpty) {
        final whereClause = _buildWhereClause(
          columns: columns,
          primaryKeys: primaryKeys,
          row: origRow,
          dialect: dialect,
          columnDataTypes: columnDataTypes,
        );

        final sql = 'UPDATE $tableRef SET ${setClauses.join(', ')} WHERE $whereClause';
        statements.add(
          TableMutationStatement(
            type: MutationType.update,
            sql: sql,
            description: 'Update row ${rowIndex + 1}',
          ),
        );
      }
    }

    // 2. Generate INSERT statements for inserted rows
    for (var i = 0; i < insertedRows.length; i++) {
      final row = insertedRows[i];
      final colNames = <String>[];
      final values = <String>[];

      for (var c = 0; c < columns.length; c++) {
        final colName = columns[c];
        final quotedCol = quoteIdentifier(colName, dialect);
        final cellVal = c < row.length ? row[c] : 'NULL';
        final colType = columnDataTypes?[colName];
        colNames.add(quotedCol);
        values.add(formatLiteral(cellVal, dialect, dataTypeName: colType));
      }

      final sql = 'INSERT INTO $tableRef (${colNames.join(', ')}) VALUES (${values.join(', ')})';
      statements.add(
        TableMutationStatement(
          type: MutationType.insert,
          sql: sql,
          description: 'Insert new row ${i + 1}',
        ),
      );
    }

    // 3. Generate DELETE statements for deleted rows
    for (final rowIndex in deletedRowIndices) {
      if (rowIndex < originalRows.length) {
        final origRow = originalRows[rowIndex];
        final whereClause = _buildWhereClause(
          columns: columns,
          primaryKeys: primaryKeys,
          row: origRow,
          dialect: dialect,
          columnDataTypes: columnDataTypes,
        );

        final sql = 'DELETE FROM $tableRef WHERE $whereClause';
        statements.add(
          TableMutationStatement(
            type: MutationType.delete,
            sql: sql,
            description: 'Delete row ${rowIndex + 1}',
          ),
        );
      }
    }

    return TableMutationPlan(
      dialect: dialect,
      tableName: tableName,
      schema: schema,
      statements: statements,
    );
  }

  static String _buildWhereClause({
    required List<String> columns,
    required List<String> primaryKeys,
    required List<String> row,
    required SqlDialect dialect,
    Map<String, String>? columnDataTypes,
  }) {
    final clauses = <String>[];

    if (primaryKeys.isNotEmpty) {
      for (final pk in primaryKeys) {
        final colIdx = columns.indexOf(pk);
        if (colIdx != -1 && colIdx < row.length) {
          final colName = quoteIdentifier(pk, dialect);
          final val = row[colIdx];
          if (val == 'NULL' || val == 'null') {
            clauses.add('$colName IS NULL');
          } else {
            final colType = columnDataTypes?[pk];
            clauses.add('$colName = ${formatLiteral(val, dialect, dataTypeName: colType)}');
          }
        }
      }
    }

    // Fallback: if no primary keys found or matched, match all columns
    if (clauses.isEmpty) {
      for (var c = 0; c < columns.length; c++) {
        final colName = columns[c];
        final quotedCol = quoteIdentifier(colName, dialect);
        final val = c < row.length ? row[c] : 'NULL';
        if (val == 'NULL' || val == 'null') {
          clauses.add('$quotedCol IS NULL');
        } else {
          final colType = columnDataTypes?[colName];
          clauses.add('$quotedCol = ${formatLiteral(val, dialect, dataTypeName: colType)}');
        }
      }
    }

    return clauses.join(' AND ');
  }
}
