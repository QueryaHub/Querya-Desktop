import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/sqlite/sqlite_result_utils.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultLimit = 200;

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

  /// Title-bar session lock. Combined with connection-form Read only (`useSSL`).
  final bool isReadOnly;

  @override
  material.State<SqliteTableView> createState() => _SqliteTableViewState();
}

class _SqliteTableViewState extends material.State<SqliteTableView> {
  SqliteLease? _lease;
  SqliteConnection? get _connection => _lease?.connection;

  bool _loading = true;
  String? _error;

  List<String> _columnNames = [];
  List<List<String>> _rows = [];
  int _rowsOnPage = 0;
  int? _totalRowCount;
  int _offset = 0;

  DataGridStagingBuffer? _stagingBuffer;
  List<String> _primaryKeys = [];
  Map<String, String> _columnDataTypes = {};
  Map<String, TableColumnMeta> _columnMeta = {};
  bool _schemaLoaded = false;
  Object? _schemaError;
  bool _isSaving = false;

  bool get _isDirty => _stagingBuffer?.isDirty ?? false;

  bool get _readOnly => widget.isReadOnly || widget.connectionRow.useSSL;

  bool get _editingEnabled => tableViewEditingEnabled(
        isView: widget.isView,
        customSqlActive: false,
        hasPrimaryKey: _primaryKeys.isNotEmpty,
        readOnly: _readOnly,
        schemaError: _schemaError,
      );

  String _qualifiedFrom() {
    return SqliteConnection.quoteIdentifier(widget.tableName);
  }

  String _browseDataSql() {
    return sqliteBrowseDataSql(
      qualifiedFrom: _qualifiedFrom(),
      primaryKeys: _primaryKeys,
      isView: widget.isView,
      limit: widget.limit,
      offset: _offset,
    );
  }

  @override
  void initState() {
    super.initState();
    _connectAndLoad();
  }

  @override
  void didUpdateWidget(covariant SqliteTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView) {
      _resetStaging();
      _disconnectCurrent();
      _connectAndLoad();
    } else if (oldWidget.isReadOnly != widget.isReadOnly ||
        oldWidget.connectionRow.useSSL != widget.connectionRow.useSSL) {
      _syncStagingToReadOnly();
    }
  }

  @override
  void dispose() {
    _resetStaging();
    _disconnectCurrent(interruptIfBusy: true);
    super.dispose();
  }

  void _resetStaging() {
    _stagingBuffer?.dispose();
    _stagingBuffer = null;
    _primaryKeys = [];
    _columnDataTypes = {};
    _columnMeta = {};
    _schemaLoaded = false;
    _schemaError = null;
    _isSaving = false;
  }

  void _syncStagingToReadOnly() {
    if (_readOnly) {
      _stagingBuffer?.dispose();
      _stagingBuffer = null;
    } else if (_columnNames.isNotEmpty) {
      _stagingBuffer = replaceTableViewStagingBuffer(
        previous: _stagingBuffer,
        columns: _columnNames,
        rows: _rows,
        enabled: _editingEnabled,
      );
    }
    if (mounted) setState(() {});
  }

  void _disconnectCurrent({bool interruptIfBusy = false}) {
    if (interruptIfBusy && _loading) {
      SqliteService.instance.interrupt(
        widget.connectionRow,
        mode: SqliteSessionMode.readOnly,
      );
    }
    if (interruptIfBusy && _isSaving) {
      SqliteService.instance.interrupt(
        widget.connectionRow,
        mode: SqliteSessionMode.tableWrite,
      );
    }
    _lease?.release();
    _lease = null;
  }

  Future<void> _connectAndLoad() async {
    _disconnectCurrent();
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _columnNames = [];
      _rows = [];
      _rowsOnPage = 0;
      _totalRowCount = null;
      _offset = 0;
      _resetStaging();
    });
    try {
      final lease = await SqliteService.instance.acquire(
        widget.connectionRow,
        mode: SqliteSessionMode.readOnly,
      );
      if (!mounted) {
        lease.release();
        return;
      }
      _lease = lease;
      await _fetch();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<T> _withTableWrite<T>(
    Future<T> Function(SqliteConnection conn) fn,
  ) async {
    if (_readOnly) {
      throw StateError('SQLite connection is read-only');
    }
    final lease = await SqliteService.instance.acquire(
      widget.connectionRow,
      mode: SqliteSessionMode.tableWrite,
    );
    try {
      return await fn(lease.connection);
    } finally {
      lease.release();
    }
  }

  Future<bool> _confirmDiscardIfNeeded() {
    return confirmDiscardTableEditsIfDirty(
      context: context,
      buffer: _stagingBuffer,
      tableTitle: widget.tableName,
    );
  }

  Future<void> _ensureSchema(SqliteConnection conn) async {
    if (_schemaLoaded) return;
    if (widget.isView) {
      _schemaLoaded = true;
      _schemaError = null;
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
      return;
    }
    final loaded = await loadTableViewSchema(
      () => conn.getTableSchema(table: widget.tableName),
    );
    final schema = loaded.schema;
    if (schema != null) {
      _primaryKeys = sqliteTableBrowserPrimaryKeys(
        declaredPrimaryKeys: schema.primaryKeys,
        isView: widget.isView,
      );
      _columnDataTypes = columnDataTypesFromSchema(schema);
      _columnMeta = columnMetaFromSchema(schema);
      if (sqliteBrowseNeedsRowidColumn(
            primaryKeys: _primaryKeys,
            isView: widget.isView,
          ) &&
          !_columnMeta.containsKey(kSqliteImplicitRowid)) {
        _columnDataTypes[kSqliteImplicitRowid] =
            sqliteImplicitRowidColumn.dataType;
        _columnMeta[kSqliteImplicitRowid] = sqliteImplicitRowidColumn;
      }
      _schemaError = null;
    } else {
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
      _schemaError = loaded.error;
    }
    _schemaLoaded = true;
  }

  void _installStagingBuffer(List<String> columns, List<List<String>> rows) {
    _stagingBuffer = replaceTableViewStagingBuffer(
      previous: _stagingBuffer,
      columns: columns,
      rows: rows,
      enabled: _editingEnabled,
    );
  }

  Future<void> _fetch() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) {
      if (mounted && _loading) {
        setState(() {
          _error = 'Not connected';
          _loading = false;
        });
      }
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _ensureSchema(conn);
      if (!mounted) return;

      // Skip COUNT(*) — it blocks the FFI isolate on large files. Next is
      // enabled when the current page is full (_canGoNext).
      _totalRowCount = null;

      final browseSql = _browseDataSql();
      final rs = await conn.execute(browseSql);

      if (!mounted) return;

      final cols = <String>[];
      if (rs.isNotEmpty) {
        cols.addAll(rs.first.keys);
      } else {
        cols.addAll(await conn.listColumnNames(table: widget.tableName));
      }

      final outRows = rs.map((row) {
        return cols.map((col) {
          return sqliteResultCellToDisplayString(
            row[col],
            dataTypeName: _columnDataTypes[col],
          );
        }).toList();
      }).toList();

      if (!mounted) return;
      setState(() {
        _columnNames = cols;
        _rows = outRows;
        _rowsOnPage = outRows.length;
        _loading = false;
        _installStagingBuffer(cols, outRows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  bool get _canGoPrevious => _offset > 0 && !_loading && !_isDirty;

  bool get _canGoNext {
    if (_loading || _isDirty) return false;
    final total = _totalRowCount;
    if (total != null) {
      return _offset + _rowsOnPage < total;
    }
    return _rowsOnPage >= widget.limit;
  }

  void _goToPreviousPage() {
    if (!_canGoPrevious || _loading) return;
    setState(() {
      _offset -= widget.limit;
      if (_offset < 0) _offset = 0;
    });
    unawaited(_fetch());
  }

  void _goToNextPage() {
    if (!_canGoNext || _loading) return;
    setState(() {
      _offset += widget.limit;
    });
    unawaited(_fetch());
  }

  Future<void> _onRefresh() async {
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    _schemaLoaded = false;
    _schemaError = null;
    await _fetch();
  }

  Future<void> _onNavigateHome() async {
    final home = widget.onNavigateHome;
    if (home == null) return;
    if (!await _confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    home();
  }

  Future<void> _applyStagedChanges() async {
    if (_readOnly) return;
    final buffer = _stagingBuffer;
    if (buffer == null || !buffer.isDirty || _isSaving) return;
    setState(() => _isSaving = true);
    final outcome = await applyTableViewStagedChanges(
      context: context,
      buffer: buffer,
      dialect: SqlDialect.sqlite,
      tableName: widget.tableName,
      primaryKeys: _primaryKeys,
      columnDataTypes: _columnDataTypes.isEmpty ? null : _columnDataTypes,
      columnMeta: _columnMeta.isEmpty ? null : _columnMeta,
      execute: (plan) async {
        await _withTableWrite((conn) async {
          if (!conn.isConnected) {
            throw StateError('Could not connect to SQLite.');
          }
          await conn.runInTransaction(() async {
            for (final stmt in plan.statements) {
              expectDmlMatchedRows(await conn.executeAffected(stmt.sql));
            }
          });
        });
      },
    );
    if (!mounted) return;
    if (outcome.isApplied) {
      final newRows = buffer.committedRows;
      buffer.dispose();
      setState(() {
        _rows = newRows;
        _rowsOnPage = newRows.length;
        _stagingBuffer = replaceTableViewStagingBuffer(
          previous: null,
          columns: _columnNames,
          rows: newRows,
          enabled: _editingEnabled,
        );
        _isSaving = false;
      });
      showAppToast(
        context: context,
        message: '${outcome.statementCount} change(s) saved',
        variant: AppToastVariant.success,
      );
      return;
    }
    setState(() => _isSaving = false);
    if (outcome.isFailed && outcome.error != null) {
      await showTableViewSaveFailedDialog(
        context: context,
        error: outcome.error!,
      );
    }
  }

  Future<void> _showDdlDialog() async {
    final conn = _connection;
    if (conn == null || !conn.isConnected) return;
    final navigator = material.Navigator.of(context, rootNavigator: true);
    unawaited(showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const material.Center(
        child: material.CircularProgressIndicator(),
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

  String _paginationLabel() {
    if (_columnNames.isEmpty && _rows.isEmpty) return '';
    final start = _offset + 1;
    final end = _offset + _rowsOnPage;
    final total = _totalRowCount;
    if (total != null) {
      return 'Showing $start-$end of $total row(s)';
    }
    return 'Showing $start-$end row(s)';
  }

  String? _statusLine() {
    final reason = tableViewEditDisabledReason(
      isView: widget.isView,
      customSqlActive: false,
      hasPrimaryKey: _primaryKeys.isNotEmpty,
      schemaLoaded: _schemaLoaded,
      readOnly: _readOnly,
      schemaError: _schemaError,
    );
    final pag = _paginationLabel();
    if (pag.isEmpty) return reason;
    if (reason != null) return '$pag · $reason';
    return pag;
  }

  material.Widget _buildChromeRow(ColorScheme cs) {
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
                onPressed: () => unawaited(_onNavigateHome()),
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
                            _paginationLabel(),
                            style: material.TextStyle(
                              fontSize: 11,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                        const Gap(6),
                        if (_stagingBuffer != null)
                          TableBrowserPendingActions(
                            buffer: _stagingBuffer!,
                            onSave: () => unawaited(_applyStagedChanges()),
                            isSaving: _isSaving,
                          ),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: _loading
                              ? null
                              : () => unawaited(_showDdlDialog()),
                          child: const Text('DDL'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed:
                              _loading ? null : () => unawaited(_onRefresh()),
                          leading: const material.Icon(
                            material.Icons.refresh_rounded,
                            size: 14,
                          ),
                          child: const Text('Refresh'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: (!_canGoPrevious || _loading)
                              ? null
                              : _goToPreviousPage,
                          leading: const material.Icon(
                            material.Icons.chevron_left_rounded,
                            size: 16,
                          ),
                          child: const Text('Prev'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed:
                              (!_canGoNext || _loading) ? null : _goToNextPage,
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
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buffer = _stagingBuffer;

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_loading) unawaited(_onRefresh());
        },
      },
      child: material.Focus(
        autofocus: true,
        child: material.Container(
          color: cs.background,
          child: material.Column(
            crossAxisAlignment: material.CrossAxisAlignment.stretch,
            children: [
              if (buffer == null)
                _buildChromeRow(cs)
              else
                ListenableBuilder(
                  listenable: buffer,
                  builder: (context, _) => _buildChromeRow(cs),
                ),
              material.Expanded(
                child: ResultsTab(
                  columns: _columnNames,
                  rows: _rows,
                  errorMessage: _error,
                  isLoading: _loading,
                  statusLine: _statusLine(),
                  showExportToolbar: true,
                  stagingBuffer: _stagingBuffer,
                  columnDataTypes:
                      _columnDataTypes.isEmpty ? null : _columnDataTypes,
                  onApplyChanges:
                      _stagingBuffer != null ? _applyStagedChanges : null,
                  isSaving: _isSaving,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
