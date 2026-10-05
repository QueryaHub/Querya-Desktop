import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_sql_editor_dialog.dart';
import 'package:querya_desktop/features/mysql/mysql_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

/// MySQL delegate for [GenericTableView].
class MysqlTableDataDelegate extends TableDataMutationDelegate {
  MysqlTableDataDelegate({
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final bool isReadOnly;

  MysqlLease? _lease;
  MysqlConnection? get _connection => _lease?.connection;

  Map<String, String> _columnDataTypes = {};
  List<String> _primaryKeys = [];

  String _qualifiedFrom() {
    final d = MysqlConnection.quoteIdentifier(database);
    final t = MysqlConnection.quoteIdentifier(tableName);
    return '$d.$t';
  }

  Future<void> _ensureReadConnection() async {
    if (_lease != null && _connection?.isConnected == true) return;
    _lease?.release();
    _lease = await MysqlService.instance.acquire(
      connectionRow,
      database: database,
      mode: MysqlSessionMode.readOnly,
    );
  }

  Future<T> withTableWrite<T>(
    Future<T> Function(MysqlConnection conn) fn,
  ) async {
    final lease = await MysqlService.instance.acquire(
      connectionRow,
      database: database,
      mode: MysqlSessionMode.tableWrite,
    );
    try {
      return await fn(lease.connection);
    } finally {
      lease.release();
    }
  }

  @override
  String browseDataSql({required int offset, required int limit}) {
    return mysqlBrowseDataSql(
      qualifiedFrom: _qualifiedFrom(),
      primaryKeys: _primaryKeys,
      limit: limit,
      offset: offset,
    );
  }

  @override
  bool isAllowedSelectQuery(String sql) => isAllowedMysqlSelectQuery(sql);

  @override
  Future<TableDataSchemaInfo> loadSchema() async {
    if (isView || isReadOnly) {
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
        database: database,
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

  List<String> _resultColumns(IResultSet rs) {
    return rs.cols.map((c) => c.name.isNotEmpty ? c.name : 'col').toList();
  }

  Future<List<List<String>>> _resultRowsAsync(IResultSet rs) async {
    final colList = rs.cols.toList();
    final out = <List<String>>[];
    var n = 0;
    for (final row in rs.rows) {
      out.add(
        List.generate(
          row.numOfColumns,
          (i) {
            final col = i < colList.length ? colList[i] : null;
            return mysqlResultCellToDisplayString(
              row.colAt(i),
              column: col,
              schemaDataType: col == null ? null : _columnDataTypes[col.name],
            );
          },
        ),
      );
      n++;
      if (n % kResultStringConvertYieldEvery == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return out;
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
          database: database,
          table: tableName,
        );
      } catch (_) {
        totalRows = null;
      }
    }

    final dataSql = browseDataSql(offset: offset, limit: limit);
    final result = await conn.execute(dataSql);

    final colNames = _resultColumns(result);
    final stringRows = await _resultRowsAsync(result);

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

    final result = await conn.execute(
      injectSqlLimit(sql, kDefaultSqlResultMaxRows),
    );
    final colNames = _resultColumns(result);
    final stringRows = await _resultRowsAsync(result);

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
    if (isReadOnly) return;
    await withTableWrite((conn) async {
      if (!conn.isConnected) {
        throw StateError('Could not connect to MySQL.');
      }
      await conn.runInTransaction(() async {
        for (final stmt in plan.statements) {
          final rs = await conn.execute(stmt.sql);
          expectDmlMatchedRows(rs.affectedRows.toInt());
        }
      });
    });
  }

  @override
  void cancel({bool interruptIfBusy = false}) {
    if (interruptIfBusy) {
      MysqlService.instance.interrupt(
        connectionRow,
        database: database,
        mode: MysqlSessionMode.readOnly,
      );
      MysqlService.instance.interrupt(
        connectionRow,
        database: database,
        mode: MysqlSessionMode.tableWrite,
      );
    }
  }

  @override
  void dispose() {
    _lease?.release();
    _lease = null;
  }
}

/// Paginated data browser for MySQL tables and views.
class MysqlTableView extends material.StatefulWidget {
  const MysqlTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.limit = _defaultLimit,
    this.onNavigateHome,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int limit;
  final material.VoidCallback? onNavigateHome;
  final bool isReadOnly;

  @override
  material.State<MysqlTableView> createState() => _MysqlTableViewState();
}

class _MysqlTableViewState extends material.State<MysqlTableView> {
  late MysqlTableDataDelegate _delegate;

  @override
  void initState() {
    super.initState();
    _delegate = _createDelegate();
  }

  @override
  void didUpdateWidget(covariant MysqlTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView ||
        oldWidget.isReadOnly != widget.isReadOnly) {
      _delegate.dispose();
      _delegate = _createDelegate();
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  MysqlTableDataDelegate _createDelegate() {
    return MysqlTableDataDelegate(
      connectionRow: widget.connectionRow,
      database: widget.database,
      tableName: widget.tableName,
      isView: widget.isView,
      isReadOnly: widget.isReadOnly,
    );
  }

  void _openSqlEditor(material.BuildContext context, GenericTableViewState state) {
    showMysqlSqlEditorDialog(
      context: context,
      initialSql: (state.customSqlActive && state.customSql != null)
          ? state.customSql!
          : state.browseDataSql(),
      browseSql: state.browseDataSql(),
      onRun: (sql) => unawaited(state.runCustomSql(sql)),
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final tableTitle = '${widget.database}.${widget.tableName}';

    return GenericTableView(
      delegate: _delegate,
      title: tableTitle,
      tableTitle: tableTitle,
      dialect: SqlDialect.mysql,
      tableName: widget.tableName,
      schema: widget.database,
      isView: widget.isView,
      isReadOnly: widget.isReadOnly,
      limit: widget.limit,
      onNavigateHome: widget.onNavigateHome,
      showExportToolbar: true,
      customToolbarBuilder: (ctx, state) {
        final cs = Theme.of(ctx).colorScheme;
        final title = '$tableTitle${widget.isView ? ' (view)' : ''}';

        return material.Container(
          height: 48,
          padding: const material.EdgeInsets.symmetric(horizontal: 12),
          decoration: material.BoxDecoration(
            color: cs.muted.withValues(alpha: 0.35),
            border: material.Border(
              bottom: material.BorderSide(
                color: cs.border.withValues(alpha: 0.4),
              ),
            ),
          ),
          child: material.Row(
            children: [
              if (widget.onNavigateHome != null) ...[
                material.Tooltip(
                  message: 'Return to server overview',
                  child: OutlineButton(
                    size: ButtonSize.small,
                    onPressed: () => unawaited(state.navigateHome()),
                    leading: const material.Icon(
                      material.Icons.dns_outlined,
                      size: 14,
                    ),
                    child: const Text('Server'),
                  ),
                ),
                const Gap(10),
              ],
              material.Icon(
                widget.isView
                    ? material.Icons.view_agenda_rounded
                    : material.Icons.table_chart_rounded,
                size: 20,
                color: cs.primary,
              ),
              const Gap(8),
              material.Expanded(
                child: material.Text(
                  title,
                  overflow: material.TextOverflow.ellipsis,
                  maxLines: 1,
                  style: material.TextStyle(
                    fontSize: 13,
                    fontWeight: material.FontWeight.w600,
                    color: cs.foreground,
                  ),
                ),
              ),
              material.Expanded(
                flex: 2,
                child: material.LayoutBuilder(
                  builder: (context, constraints) {
                    return material.SingleChildScrollView(
                      scrollDirection: material.Axis.horizontal,
                      child: material.ConstrainedBox(
                        constraints: material.BoxConstraints(
                          minWidth: constraints.maxWidth,
                        ),
                        child: material.Row(
                          mainAxisAlignment: material.MainAxisAlignment.end,
                          mainAxisSize: material.MainAxisSize.min,
                          children: [
                            material.Container(
                              padding: const material.EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: material.BoxDecoration(
                                color: cs.muted.withValues(alpha: 0.4),
                                borderRadius: material.BorderRadius.circular(4),
                              ),
                              child: material.Text(
                                state.paginationLabel(),
                                style: material.TextStyle(
                                  fontSize: 11,
                                  color: cs.mutedForeground,
                                ),
                              ),
                            ),
                            const Gap(6),
                            if (!widget.isView) ...[
                              state.buildEditModeButton(),
                              const Gap(4),
                            ],
                            OutlineButton(
                              size: ButtonSize.small,
                              onPressed: () => _openSqlEditor(ctx, state),
                              leading: const material.Icon(
                                material.Icons.code_rounded,
                                size: 15,
                              ),
                              child: const Text('SQL'),
                            ),
                            if (state.customSqlActive) ...[
                              const Gap(4),
                              OutlineButton(
                                size: ButtonSize.small,
                                onPressed: () => unawaited(state.exitCustomMode()),
                                leading: const material.Icon(
                                  material.Icons.table_chart_rounded,
                                  size: 15,
                                ),
                                child: const Text('Browse'),
                              ),
                            ],
                            const Gap(4),
                            OutlineButton(
                              size: ButtonSize.small,
                              onPressed: (!state.canGoPrevious || state.isLoading)
                                  ? null
                                  : state.goToPreviousPage,
                              leading: const material.Icon(
                                material.Icons.chevron_left_rounded,
                                size: 16,
                              ),
                              child: const Text('Prev'),
                            ),
                            const Gap(4),
                            OutlineButton(
                              size: ButtonSize.small,
                              onPressed: (!state.canGoNext || state.isLoading)
                                  ? null
                                  : state.goToNextPage,
                              leading: const material.Icon(
                                material.Icons.chevron_right_rounded,
                                size: 16,
                              ),
                              child: const Text('Next'),
                            ),
                            const Gap(8),
                            OutlineButton(
                              size: ButtonSize.small,
                              onPressed: state.isLoading
                                  ? null
                                  : () => unawaited(state.refresh()),
                              leading: const material.Icon(
                                material.Icons.refresh_rounded,
                                size: 14,
                              ),
                              child: const Text('Refresh'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
