import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/erd/erd_catalog.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';
import 'package:querya_desktop/features/workspace/table_data_delegate.dart';

/// Where the diagram reads its tables from: the whole schema, or the tables
/// around one table. Names are as the diagram shows them (`schema.table`
/// outside the current schema).
abstract interface class ErdSource {
  Future<ErdSchema> loadSchema();

  /// [table] and the tables within [depth] foreign keys of it, either way.
  Future<ErdSchema> loadNeighbourhood(String table, {int depth = 1});
}

/// Reads the catalog through a query runner for one dialect.
class SqlErdSource implements ErdSource {
  const SqlErdSource({required this.delegate, required this.dialect});

  final SqlExecutionDelegate delegate;
  final SqlDialect dialect;

  @override
  Future<ErdSchema> loadSchema() => ErdCatalog.load(delegate, dialect);

  @override
  Future<ErdSchema> loadNeighbourhood(String table, {int depth = 1}) =>
      ErdCatalog.loadNeighbourhood(
        delegate,
        dialect,
        table: table,
        depth: depth,
      );
}

/// Runs catalog queries on a table browser's own read-only session, through
/// [TableDataMutationDelegate.loadCustomSql]. The table delegate keeps its own
/// connection, so the diagram never borrows the SQL editor's session.
class TableDataSqlAdapter implements SqlExecutionDelegate {
  const TableDataSqlAdapter(this.table);

  final TableDataMutationDelegate table;

  @override
  Future<SqlExecutionResult> executeQuery(
    String sql, {
    int? limit,
    Duration? timeout,
  }) async {
    final page = await table.loadCustomSql(sql);
    return SqlExecutionResult(columns: page.columns, rows: page.rows);
  }

  @override
  Future<String> explainQuery(String sql) =>
      Future.error(UnsupportedError('Explain is not used by the diagram'));

  @override
  bool get supportsExplain => false;

  @override
  Future<void> cancelQuery() async => table.cancel(interruptIfBusy: true);

  @override
  bool get supportsTransactions => false;
}
