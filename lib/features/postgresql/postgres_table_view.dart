import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/postgres_sql.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_result_utils.dart';
import 'package:querya_desktop/features/postgresql/postgres_sql_editor_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_privileges_dialog.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_toolbar.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// PostgreSQL delegate for [GenericTableView].
class PostgresTableDataDelegate extends TableDataMutationDelegate {
  PostgresTableDataDelegate({
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.tableName,
    this.isView = false,
    this.isMaterializedView = false,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String tableName;
  final bool isView;
  final bool isMaterializedView;

  PgLease? _lease;
  PostgresConnection? get _connection => _lease?.connection;

  Map<String, String> _columnDataTypes = {};
  List<String> _primaryKeys = [];

  Future<void> _ensureReadConnection() async {
    if (_lease != null && _connection?.isConnected == true) return;
    _lease?.release();
    _lease = await PostgresService.instance.acquire(
      connectionRow,
      database: database,
      mode: PgSessionMode.readOnly,
    );
  }

  Future<T> withTableWrite<T>(
    Future<T> Function(PostgresConnection conn) fn,
  ) async {
    final lease = await PostgresService.instance.acquire(
      connectionRow,
      database: database,
      mode: PgSessionMode.tableWrite,
    );
    try {
      return await fn(lease.connection);
    } finally {
      lease.release();
    }
  }

  @override
  String browseDataSql({required int offset, required int limit}) {
    final schemaQ = quotePostgresIdentifier(schema);
    final tableQ = quotePostgresIdentifier(tableName);
    return postgresBrowseDataSql(
      qualifiedFrom: '$schemaQ.$tableQ',
      primaryKeys: _primaryKeys,
      limit: limit,
      offset: offset,
    );
  }

  @override
  bool isAllowedSelectQuery(String sql) => isAllowedPostgresSelectQuery(sql);

  @override
  Future<TableDataSchemaInfo> loadSchema() async {
    if (isView || isMaterializedView) {
      _primaryKeys = [];
      _columnDataTypes = {};
      return const TableDataSchemaInfo();
    }
    await _ensureReadConnection();
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    final loaded = await loadTableViewSchema(
      () => conn.getTableSchema(
        schema: schema,
        table: tableName,
      ),
    );
    final s = loaded.schema;
    if (s != null) {
      _primaryKeys = List<String>.from(s.primaryKeys);
      _columnDataTypes = columnDataTypesFromSchema(s);
      return TableDataSchemaInfo(
        primaryKeys: _primaryKeys,
        columnDataTypes: _columnDataTypes,
        columnMeta: columnMetaFromSchema(s),
      );
    }
    _primaryKeys = [];
    _columnDataTypes = {};
    return TableDataSchemaInfo(
      schemaError: loaded.error,
    );
  }

  Future<List<List<String>>> _postgresRowsToDisplayStrings(
    Result result,
    List<String> colNames,
  ) async {
    final rawRows = <List<Object?>>[
      for (final row in result)
        List<Object?>.generate(row.length, (i) => row[i]),
    ];
    return convertPostgresResultRowsToStringsAdaptive(
      PostgresResultConvertJob(
        rowValues: rawRows,
        columnTypeOids: [
          for (final c in result.schema.columns) c.typeOid,
        ],
        columnDataTypes: [
          for (final n in colNames) _columnDataTypes[n],
        ],
      ),
    );
  }

  @override
  Future<TableDataPage> loadPage({
    required int offset,
    required int limit,
    bool refreshCount = false,
  }) async {
    await _ensureReadConnection();
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    int? totalRows;
    if (refreshCount) {
      try {
        totalRows = await conn.estimateTableRows(
          schema: schema,
          table: tableName,
        );
      } catch (_) {
        totalRows = null;
      }
    }

    final dataSql = browseDataSql(offset: offset, limit: limit);
    final result = await conn.execute(dataSql);

    final colNames = List<String>.generate(
      result.schema.columns.length,
      (i) => result.schema.columns[i].columnName ?? 'col_$i',
    );

    final stringRows = await _postgresRowsToDisplayStrings(result, colNames);

    return TableDataPage(
      columns: colNames,
      rows: stringRows,
      totalRowCount: totalRows,
    );
  }

  @override
  Future<TableDataPage> loadCustomSql(String sql) async {
    await _ensureReadConnection();
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    final result = await conn.execute(sql);
    final colNames = List<String>.generate(
      result.schema.columns.length,
      (i) => result.schema.columns[i].columnName ?? 'col_$i',
    );

    final stringRows = await _postgresRowsToDisplayStrings(result, colNames);

    return TableDataPage(
      columns: colNames,
      rows: stringRows,
      totalRowCount: null,
    );
  }

  @override
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  }) async {
    await withTableWrite((conn) async {
      if (!conn.isConnected) {
        throw StateError('Could not connect to PostgreSQL.');
      }
      await runPostgresStatementsInTransaction(
        (sql) async {
          final result = await conn.execute(sql, timeout: timeout);
          if (sql != 'BEGIN' && sql != 'COMMIT' && sql != 'ROLLBACK') {
            expectDmlMatchedRows(result.affectedRows);
          }
        },
        plan.statements.map((s) => s.sql),
      );
    });
  }

  Future<void> refreshMaterializedView() async {
    await withTableWrite((conn) {
      return conn.refreshMaterializedView(schema, tableName);
    });
  }

  @override
  void cancel({bool interruptIfBusy = false}) {
    if (interruptIfBusy) {
      PostgresService.instance.interrupt(
        connectionRow,
        database: database,
        mode: PgSessionMode.readOnly,
      );
      PostgresService.instance.interrupt(
        connectionRow,
        database: database,
        mode: PgSessionMode.tableWrite,
      );
    }
  }

  @override
  void dispose() {
    _lease?.release();
    _lease = null;
  }
}

/// Paginated data browser for PostgreSQL tables, views, and materialized views.
class PostgresTableView extends material.StatefulWidget {
  const PostgresTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.schema,
    required this.tableName,
    this.isView = false,
    this.isMaterializedView = false,
    this.limit = kPostgresBrowseDefaultRowLimit,
    this.onNavigateHome,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String schema;
  final String tableName;
  final bool isView;
  final bool isMaterializedView;
  final int limit;
  final material.VoidCallback? onNavigateHome;

  @override
  material.State<PostgresTableView> createState() => _PostgresTableViewState();
}

class _PostgresTableViewState extends material.State<PostgresTableView> {
  late PostgresTableDataDelegate _delegate;

  @override
  void initState() {
    super.initState();
    _delegate = _createDelegate();
  }

  @override
  void didUpdateWidget(covariant PostgresTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.schema != widget.schema ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isMaterializedView != widget.isMaterializedView ||
        oldWidget.isView != widget.isView) {
      _delegate.dispose();
      _delegate = _createDelegate();
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  PostgresTableDataDelegate _createDelegate() {
    return PostgresTableDataDelegate(
      connectionRow: widget.connectionRow,
      database: widget.database,
      schema: widget.schema,
      tableName: widget.tableName,
      isView: widget.isView,
      isMaterializedView: widget.isMaterializedView,
    );
  }

  void _openPrivileges(material.BuildContext context) {
    final conn = _delegate._connection;
    if (conn == null || !conn.isConnected) return;
    showPostgresTablePrivilegesDialog(
      context: context,
      connection: conn,
      schema: widget.schema,
      tableName: widget.tableName,
    );
  }

  void _openSqlEditor(material.BuildContext context, GenericTableViewState state) {
    showPostgresSqlEditorDialog(
      context: context,
      initialSql: (state.customSqlActive && state.customSql != null)
          ? state.customSql!
          : state.browseDataSql(),
      browseSql: state.browseDataSql(),
      onRun: (sql) => unawaited(state.runCustomSql(sql)),
    );
  }

  Future<void> _refreshMaterializedView(
    material.BuildContext context,
    GenericTableViewState state,
  ) async {
    if (state.isLoading) return;
    if (!await state.confirmDiscardIfNeeded()) return;
    try {
      await _delegate.refreshMaterializedView();
      await state.refresh();
    } catch (e) {
      if (!context.mounted) return;
      showAppToast(
        context: context,
        message: 'Refresh materialized view failed: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    final tableTitle = '${widget.schema}.${widget.tableName}';

    return GenericTableView(
      delegate: _delegate,
      title: tableTitle,
      tableTitle: tableTitle,
      dialect: SqlDialect.postgres,
      tableName: widget.tableName,
      schema: widget.schema,
      isView: widget.isView,
      isMaterializedView: widget.isMaterializedView,
      limit: widget.limit,
      onNavigateHome: widget.onNavigateHome,
      showExportToolbar: true,
      customToolbarBuilder: (ctx, state) {
        return PostgresTableToolbar(
          title: '$tableTitle${widget.isMaterializedView ? ' (materialized view)' : widget.isView ? ' (view)' : ''}',
          paginationLabel: state.paginationLabel(),
          tableIcon: widget.isMaterializedView
              ? material.Icons.dynamic_feed_rounded
              : widget.isView
                  ? material.Icons.view_agenda_rounded
                  : material.Icons.table_chart_rounded,
          customSqlActive: state.customSqlActive,
          isMaterializedView: widget.isMaterializedView,
          loading: state.isLoading,
          canGoPrevious: state.canGoPrevious,
          canGoNext: state.canGoNext,
          onNavigateHome: widget.onNavigateHome == null
              ? null
              : () => unawaited(state.navigateHome()),
          onOpenSql: () => _openSqlEditor(ctx, state),
          onOpenPrivileges: () => _openPrivileges(ctx),
          onRefreshMaterializedView: () =>
              unawaited(_refreshMaterializedView(ctx, state)),
          onExitCustomMode: () => unawaited(state.exitCustomMode()),
          onGoPrevious: state.goToPreviousPage,
          onGoNext: state.goToNextPage,
          onRefresh: () => unawaited(state.refresh()),
          editAction: widget.isView || widget.isMaterializedView
              ? null
              : state.buildEditModeButton(),
        );
      },
    );
  }
}
