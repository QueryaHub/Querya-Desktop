import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_result_utils.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

/// SQLite delegate for [GenericTableView].
class SqliteTableDataDelegate extends TableDataMutationDelegate {
  SqliteTableDataDelegate({
    required this.connectionRow,
    required this.tableName,
    this.isView = false,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final String tableName;
  final bool isView;
  final bool isReadOnly;

  SqliteLease? _lease;
  SqliteConnection? get _connection => _lease?.connection;

  Map<String, String> _columnDataTypes = {};
  List<String> _primaryKeys = [];

  bool get effectiveReadOnly => isReadOnly || connectionRow.useSSL;

  String _qualifiedFrom() => SqliteConnection.quoteIdentifier(tableName);

  Future<SqliteConnection?> ensureBrowseConnection() async {
    final current = _connection;
    if (current != null && current.isConnected) return current;
    _lease?.release();
    _lease = null;
    try {
      final lease = await SqliteService.instance.acquire(
        connectionRow,
        mode: SqliteSessionMode.readOnly,
      );
      _lease = lease;
      return lease.connection;
    } catch (_) {
      return null;
    }
  }

  Future<T> withTableWrite<T>(
    Future<T> Function(SqliteConnection conn) fn,
  ) async {
    final lease = await SqliteService.instance.acquire(
      connectionRow,
      mode: SqliteSessionMode.tableWrite,
    );
    try {
      return await fn(lease.connection);
    } finally {
      lease.release();
    }
  }

  @override
  ConnectionRow? get auditConnection => connectionRow;

  @override
  String? get auditDatabaseName => connectionRow.host;

  @override
  String browseDataSql({required int offset, required int limit}) {
    return sqliteBrowseDataSql(
      qualifiedFrom: _qualifiedFrom(),
      primaryKeys: _primaryKeys,
      isView: isView,
      limit: limit,
      offset: offset,
    );
  }

  @override
  bool isAllowedSelectQuery(String sql) => true;

  @override
  Future<TableDataSchemaInfo> loadSchema() async {
    if (isView || effectiveReadOnly) {
      _primaryKeys = [];
      _columnDataTypes = {};
      return const TableDataSchemaInfo();
    }
    final conn = await ensureBrowseConnection();
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    final loaded = await loadTableViewSchema(
      () => conn.getTableSchema(table: tableName),
    );
    final s = loaded.schema;
    if (s != null) {
      _primaryKeys = sqliteTableBrowserPrimaryKeys(
        declaredPrimaryKeys: s.primaryKeys,
        isView: isView,
      );
      _columnDataTypes = columnDataTypesFromSchema(s);
      final colMeta = columnMetaFromSchema(s);
      if (sqliteBrowseNeedsRowidColumn(
            primaryKeys: _primaryKeys,
            isView: isView,
          ) &&
          !colMeta.containsKey(kSqliteImplicitRowid)) {
        _columnDataTypes[kSqliteImplicitRowid] =
            sqliteImplicitRowidColumn.dataType;
        colMeta[kSqliteImplicitRowid] = sqliteImplicitRowidColumn;
      }
      return TableDataSchemaInfo(
        primaryKeys: _primaryKeys,
        columnDataTypes: _columnDataTypes,
        columnMeta: colMeta,
      );
    }
    _primaryKeys = [];
    _columnDataTypes = {};
    return TableDataSchemaInfo(
      schemaError: loaded.error,
    );
  }

  @override
  Future<TableDataPage> loadPage({
    required int offset,
    required int limit,
    bool refreshCount = false,
  }) async {
    final conn = await ensureBrowseConnection();
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    final dataSql = browseDataSql(offset: offset, limit: limit);
    final rs = await conn.execute(dataSql);

    final cols = <String>[];
    if (rs.isNotEmpty) {
      cols.addAll(rs.first.keys);
    } else {
      cols.addAll(await conn.listColumnNames(table: tableName));
    }

    final outRows = rs.map((row) {
      return cols.map((col) {
        return sqliteResultCellToDisplayString(
          row[col],
          dataTypeName: _columnDataTypes[col],
        );
      }).toList();
    }).toList();

    return TableDataPage(
      columns: cols,
      rows: outRows,
      totalRowCount: null,
    );
  }

  @override
  Future<TableDataPage> loadCustomSql(String sql) async {
    final conn = await ensureBrowseConnection();
    if (conn == null || !conn.isConnected) {
      throw StateError('Not connected');
    }

    final rs = await conn.execute(sql);
    final cols = <String>[];
    if (rs.isNotEmpty) {
      cols.addAll(rs.first.keys);
    } else {
      cols.addAll(await conn.listColumnNames(table: tableName));
    }

    final outRows = rs.map((row) {
      return cols.map((col) {
        return sqliteResultCellToDisplayString(
          row[col],
          dataTypeName: _columnDataTypes[col],
        );
      }).toList();
    }).toList();

    return TableDataPage(
      columns: cols,
      rows: outRows,
      totalRowCount: null,
    );
  }

  @override
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  }) async {
    if (effectiveReadOnly) return;
    await withTableWrite((conn) async {
      if (!conn.isConnected) {
        throw StateError('Could not connect to SQLite.');
      }
      await conn.runInTransaction(() async {
        for (final stmt in plan.statements) {
          expectDmlMatchedRows(await conn.executeAffected(stmt.sql));
        }
      });
    });
  }

  @override
  void cancel({bool interruptIfBusy = false}) {
    if (interruptIfBusy) {
      SqliteService.instance.interrupt(
        connectionRow,
        mode: SqliteSessionMode.readOnly,
      );
      SqliteService.instance.interrupt(
        connectionRow,
        mode: SqliteSessionMode.tableWrite,
      );
    }
  }

  @override
  void dispose() {
    _lease?.release();
    _lease = null;
  }
}

/// Paginated data browser for SQLite tables and views.
class SqliteTableView extends material.StatefulWidget {
  const SqliteTableView({
    super.key,
    required this.connectionRow,
    required this.tableName,
    this.isView = false,
    this.limit = _defaultLimit,
    this.onNavigateHome,
    this.isReadOnly = false,
  });

  final ConnectionRow connectionRow;
  final String tableName;
  final bool isView;
  final int limit;
  final VoidCallback? onNavigateHome;
  final bool isReadOnly;

  @override
  material.State<SqliteTableView> createState() => _SqliteTableViewState();
}

class _SqliteTableViewState extends material.State<SqliteTableView> {
  late SqliteTableDataDelegate _delegate;

  @override
  void initState() {
    super.initState();
    _delegate = _createDelegate();
  }

  @override
  void didUpdateWidget(covariant SqliteTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView ||
        oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.connectionRow.useSSL != widget.connectionRow.useSSL) {
      _delegate.dispose();
      _delegate = _createDelegate();
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  SqliteTableDataDelegate _createDelegate() {
    return SqliteTableDataDelegate(
      connectionRow: widget.connectionRow,
      tableName: widget.tableName,
      isView: widget.isView,
      isReadOnly: widget.isReadOnly,
    );
  }

  Future<void> _showDdlDialog() async {
    final conn = await _delegate.ensureBrowseConnection();
    if (!mounted || conn == null || !conn.isConnected) return;
    final navigator = material.Navigator.of(context, rootNavigator: true);
    unawaited(showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const material.Center(
        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
      ),
    ));
    try {
      final ddl = await conn.getObjectDdl(widget.tableName);
      if (navigator.canPop()) navigator.pop();
      if (!mounted) return;
      await showAppDialog<void>(
        context: context,
        builder: (ctx) => QueryaDialogCard(
          constraints:
              const material.BoxConstraints(maxWidth: 640, maxHeight: 500),
          child: material.Padding(
            padding: const material.EdgeInsets.all(20),
            child: material.Column(
              mainAxisSize: material.MainAxisSize.min,
              crossAxisAlignment: material.CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.isView ? "View" : "Table"} DDL · ${widget.tableName}',
                ).semiBold().large(),
                const Gap(16),
                material.Expanded(
                  child: material.Container(
                    decoration:
                        SqlEditorChrome.inlineFieldDecorationFromContext(ctx),
                    child: QueryaCodeEditor(
                      controller: material.TextEditingController(text: ddl),
                      language: QueryaCodeLanguage.sql,
                      readOnly: true,
                      fontSize: 12,
                      variant: QueryaCodeEditorVariant.material,
                      contentPadding: const material.EdgeInsets.all(12),
                    ),
                  ),
                ),
                const Gap(16),
                material.Align(
                  alignment: material.Alignment.centerRight,
                  child: OutlineButton(
                    onPressed: () => material.Navigator.of(ctx).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (navigator.canPop()) navigator.pop();
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Failed to fetch DDL: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  @override
  material.Widget build(material.BuildContext context) {
    return GenericTableView(
      delegate: _delegate,
      title: widget.tableName,
      tableTitle: widget.tableName,
      dialect: SqlDialect.sqlite,
      tableName: widget.tableName,
      isView: widget.isView,
      isReadOnly: _delegate.effectiveReadOnly,
      limit: widget.limit,
      onNavigateHome: widget.onNavigateHome,
      showExportToolbar: true,
      customToolbarBuilder: (ctx, state) {
        final cs = Theme.of(ctx).colorScheme;
        final title = '${widget.tableName}${widget.isView ? ' (view)' : ''}';

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
                  message: 'Return to overview',
                  child: OutlineButton(
                    size: ButtonSize.small,
                    onPressed: () => unawaited(state.navigateHome()),
                    leading: const material.Icon(
                      material.Icons.dns_outlined,
                      size: 14,
                    ),
                    child: const Text('Overview'),
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
                              onPressed: state.isLoading
                                  ? null
                                  : () => unawaited(_showDdlDialog()),
                              child: const Text('DDL'),
                            ),
                            const Gap(4),
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
