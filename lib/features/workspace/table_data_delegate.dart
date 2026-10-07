import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';

/// Represents a loaded data page with column names and string rows.
@immutable
class TableDataPage {
  const TableDataPage({
    required this.columns,
    required this.rows,
    this.totalRowCount,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final int? totalRowCount;
}

/// Metadata about the table schema needed for in-place editing.
@immutable
class TableDataSchemaInfo {
  const TableDataSchemaInfo({
    this.primaryKeys = const [],
    this.columnDataTypes = const {},
    this.columnMeta = const {},
    this.schemaError,
  });

  final List<String> primaryKeys;
  final Map<String, String> columnDataTypes;
  final Map<String, TableColumnMeta> columnMeta;
  final Object? schemaError;

  bool get hasPrimaryKey => primaryKeys.isNotEmpty;
}

/// Delegate interface for database-specific table data browsing, custom SQL
/// loading, schema retrieval, and staging DML mutations in [GenericTableView].
abstract class TableDataMutationDelegate {
  /// Loads table data for the given pagination parameters.
  /// When [refreshCount] is true, delegates that support table row estimates
  /// should recalculate the total row count.
  Future<TableDataPage> loadPage({
    required int offset,
    required int limit,
    bool refreshCount = false,
  });

  /// Loads custom SQL query data.
  Future<TableDataPage> loadCustomSql(String sql);

  /// Resolves table schema (primary keys, column types, column metadata).
  Future<TableDataSchemaInfo> loadSchema();

  /// Applies staged changes. Implementations can either execute the SQL plan
  /// or perform driver-native batch mutations.
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  });

  /// SQL query string used to browse table data at the given offset/limit.
  String browseDataSql({required int offset, required int limit});

  /// Checks if [sql] is an allowed select query for custom SQL execution.
  bool isAllowedSelectQuery(String sql);

  /// Connection this delegate writes through (audit trail of applied edits).
  ConnectionRow? get auditConnection => null;

  /// Database the edits are applied in, for the audit trail.
  String? get auditDatabaseName => null;

  /// Cancels an in-flight operation if supported.
  void cancel({bool interruptIfBusy = false}) {}

  /// Releases delegate resources (leases, connections, sessions).
  void dispose() {}
}
