import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/editor/querya_code_editor.dart';
import 'package:querya_desktop/core/editor/querya_code_language.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/extensions/models/extension_driver_capabilities.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_driver_recovery_banner.dart';
import 'package:querya_desktop/features/extensions/extension_table_toolbar.dart';
import 'package:querya_desktop/features/workspace/workspace.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultPageSize = 200;

/// Extension driver delegate for [GenericTableView].
class ExtensionTableDataDelegate extends TableDataMutationDelegate {
  ExtensionTableDataDelegate({
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.whereClauseProvider,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final String Function()? whereClauseProvider;

  ExtensionDriverCapabilities? _capabilities;
  List<String> _primaryKeys = const [];

  String get qualifiedName => '`$database`.`$tableName`';

  String get _whereClause => whereClauseProvider?.call() ?? '';

  Future<ExtensionDriverCapabilities> getCapabilities() async {
    _capabilities ??= await ExtensionDriverSession.instance
        .getCapabilities(connectionRow);
    return _capabilities!;
  }

  @override
  ConnectionRow? get auditConnection => connectionRow;

  @override
  String? get auditDatabaseName => database;

  @override
  String browseDataSql({required int offset, required int limit}) {
    return 'SELECT * FROM $qualifiedName$_whereClause LIMIT $limit OFFSET $offset';
  }

  @override
  bool isAllowedSelectQuery(String sql) => true;

  @override
  Future<TableDataSchemaInfo> loadSchema() async {
    final caps = await getCapabilities();
    if (isView || !caps.supportsMutations) {
      _primaryKeys = const [];
      return const TableDataSchemaInfo();
    }

    final loaded = await loadTableViewSchema(
      () => ExtensionDriverSession.instance.getTableSchema(
        connectionRow,
        database: database,
        tableName: tableName,
      ),
    );
    final s = loaded.schema;
    if (s != null) {
      _primaryKeys = List<String>.from(s.primaryKeys);
      return TableDataSchemaInfo(
        primaryKeys: _primaryKeys,
        columnDataTypes: columnDataTypesFromSchema(s),
        columnMeta: columnMetaFromSchema(s),
      );
    }
    _primaryKeys = const [];
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
    await getCapabilities();
    final dataResult = await ExtensionDriverSession.instance.query(
      connectionRow,
      'SELECT * FROM $qualifiedName$_whereClause LIMIT $limit OFFSET $offset',
    );

    int? totalRows;
    if (refreshCount) {
      try {
        final countQuery = 'SELECT count(*) AS cnt FROM $qualifiedName$_whereClause';
        final countResult = await ExtensionDriverSession.instance.query(
          connectionRow,
          countQuery,
        );
        if (countResult.rows.isNotEmpty && countResult.rows.first.isNotEmpty) {
          totalRows = int.tryParse(countResult.rows.first.first);
        }
      } catch (_) {
        try {
          final fallbackQuery = 'SELECT count() AS cnt FROM $qualifiedName$_whereClause';
          final countResult = await ExtensionDriverSession.instance.query(
            connectionRow,
            fallbackQuery,
          );
          if (countResult.rows.isNotEmpty && countResult.rows.first.isNotEmpty) {
            totalRows = int.tryParse(countResult.rows.first.first);
          }
        } catch (_) {}
      }
    }

    return TableDataPage(
      columns: dataResult.columns,
      rows: dataResult.rows,
      totalRowCount: totalRows,
    );
  }

  @override
  Future<TableDataPage> loadCustomSql(String sql) async {
    final dataResult = await ExtensionDriverSession.instance.query(
      connectionRow,
      sql,
    );
    return TableDataPage(
      columns: dataResult.columns,
      rows: dataResult.rows,
      totalRowCount: null,
    );
  }

  @override
  Future<void> applyStagedChanges({
    required TableMutationPlan plan,
    required DataGridStagingBuffer buffer,
    Duration? timeout,
  }) async {
    final primaryKeys = _primaryKeys;
    if (primaryKeys.isEmpty) {
      throw StateError(
        'Cannot save: no primary key is available for $tableName. Edits would match all rows.',
      );
    }

    final mutations = <Map<String, dynamic>>[];
    final columns = buffer.columns;

    // 1. Updates
    for (final entry in buffer.modifiedCells.entries) {
      final rowIndex = entry.key;
      final colMap = entry.value;
      final origRow = buffer.originalRows[rowIndex];

      final whereMap = <String, dynamic>{};
      for (final pk in primaryKeys) {
        final idx = columns.indexOf(pk);
        if (idx != -1 && idx < origRow.length) {
          whereMap[pk] = origRow[idx];
        }
      }

      final setMap = <String, dynamic>{};
      for (final colEntry in colMap.entries) {
        final colName = columns[colEntry.key];
        final val = colEntry.value;
        setMap[colName] = val == TableMutationEngine.kNullSentinel ? null : val;
      }

      mutations.add({
        'type': 'update',
        'where': whereMap,
        'set': setMap,
      });
    }

    // 2. Inserts
    for (final row in buffer.insertedRows) {
      final valuesMap = <String, dynamic>{};
      for (var c = 0; c < columns.length; c++) {
        final val = c < row.length ? row[c] : null;
        valuesMap[columns[c]] = (val == null ||
                val == TableMutationEngine.kNullSentinel ||
                val == 'NULL')
            ? null
            : val;
      }
      mutations.add({
        'type': 'insert',
        'values': valuesMap,
      });
    }

    // 3. Deletes
    for (final rowIndex in buffer.deletedRowIndices) {
      final origRow = buffer.originalRows[rowIndex];
      final whereMap = <String, dynamic>{};
      for (final pk in primaryKeys) {
        final idx = columns.indexOf(pk);
        if (idx != -1 && idx < origRow.length) {
          whereMap[pk] = origRow[idx];
        }
      }
      mutations.add({
        'type': 'delete',
        'where': whereMap,
      });
    }

    if (mutations.isNotEmpty) {
      final res = await ExtensionDriverSession.instance.mutate(
        connectionRow,
        database: database,
        tableName: tableName,
        mutations: mutations,
      );
      final affectedRows = res['affectedRows'];
      if (affectedRows is! int) {
        throw StateError(
          'Save failed: driver did not return an affectedRows count.',
        );
      }
      expectDmlMatchedRows(affectedRows);
    }
  }

  @override
  void dispose() {}
}

/// Paginated data browser for extension driver tables and views with async count and toolbar.
class ExtensionTableView extends material.StatefulWidget {
  const ExtensionTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.pageSize = _defaultPageSize,
    this.onNavigateHome,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int pageSize;
  final VoidCallback? onNavigateHome;

  @override
  material.State<ExtensionTableView> createState() =>
      _ExtensionTableViewState();
}

class _ExtensionTableViewState extends material.State<ExtensionTableView> {
  late ExtensionTableDataDelegate _delegate;
  final _filterController = material.TextEditingController();
  bool _filterActive = false;
  bool _restartingDriver = false;

  final GlobalKey<GenericTableViewState> _genericKey =
      GlobalKey<GenericTableViewState>();

  String get _whereClause {
    final text = _filterController.text.trim();
    return text.isEmpty ? '' : ' WHERE $text';
  }

  @override
  void initState() {
    super.initState();
    _delegate = _createDelegate();
  }

  @override
  void didUpdateWidget(covariant ExtensionTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.isView != widget.isView) {
      _delegate.dispose();
      _filterController.clear();
      _filterActive = false;
      _delegate = _createDelegate();
    }
  }

  @override
  void dispose() {
    _delegate.dispose();
    _filterController.dispose();
    super.dispose();
  }

  ExtensionTableDataDelegate _createDelegate() {
    return ExtensionTableDataDelegate(
      connectionRow: widget.connectionRow,
      database: widget.database,
      tableName: widget.tableName,
      isView: widget.isView,
      whereClauseProvider: () => _whereClause,
    );
  }

  bool _isDriverError(String? err) {
    if (err == null) return false;
    return err.contains('PluginCrashedException') ||
        err.contains('PluginDeadlockException') ||
        err.contains('PluginProtocolTimeoutException') ||
        err.contains('TimeoutException') ||
        err.contains('SocketException') ||
        err.contains('Broken pipe') ||
        err.contains('JsonRpcStdioClient') ||
        err.contains('Connection') ||
        err.contains('is not started');
  }

  Future<void> _restartDriver(GenericTableViewState state) async {
    if (_restartingDriver) return;
    if (!await state.confirmDiscardIfNeeded()) return;
    if (!mounted) return;

    setState(() {
      _restartingDriver = true;
    });
    try {
      await ExtensionDriverSession.instance.restart(widget.connectionRow);
      if (!mounted) return;
      showAppToast(
        context: context,
        message: 'Driver restarted successfully',
        variant: AppToastVariant.success,
      );
      setState(() {
        _restartingDriver = false;
      });
      await state.refresh();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _restartingDriver = false;
      });
      showAppToast(
        context: context,
        message: 'Driver restart failed: $e',
        variant: AppToastVariant.error,
      );
    }
  }

  Future<void> _openDdlDialog() async {
    final navigator = material.Navigator.of(context, rootNavigator: true);
    unawaited(showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const material.Center(
        child: QueryaSpinner(size: QueryaSpinnerSize.lg),
      ),
    ));

    try {
      final meta = await ExtensionDriverSession.instance.getObjectMetadata(
        widget.connectionRow,
        nodeId: widget.tableName,
        nodeType: widget.isView ? 'view' : 'table',
      );
      if (navigator.canPop()) navigator.pop();
      if (!mounted) return;

      final ddlText = meta.ddl?.trim().isNotEmpty == true
          ? meta.ddl!
          : '-- No DDL metadata returned by extension driver for ${widget.tableName}\nSELECT * FROM ${_delegate.qualifiedName} LIMIT 10;';

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
                      controller: material.TextEditingController(text: ddlText),
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

  void _applyFilter(GenericTableViewState state) {
    unawaited(state.refresh());
  }

  void _clearFilter(GenericTableViewState state) {
    _filterController.clear();
    unawaited(state.refresh());
  }

  @override
  material.Widget build(material.BuildContext context) {
    final kind = widget.isView ? 'View' : 'Table';
    final tableTitle = '$kind · ${widget.database}.${widget.tableName}';

    return GenericTableView(
      key: _genericKey,
      delegate: _delegate,
      showRelations: false,
      title: tableTitle,
      tableTitle: '${widget.database}.${widget.tableName}',
      dialect: SqlDialect.postgres, // Generic fallback
      tableName: widget.tableName,
      schema: widget.database,
      isView: widget.isView,
      limit: widget.pageSize,
      onNavigateHome: widget.onNavigateHome,
      showExportToolbar: false,
      errorAction: _isDriverError(_genericKey.currentState?.error)
          ? ExtensionDriverRecoveryBanner(
              onRestart: () {
                final st = _genericKey.currentState;
                if (st != null) unawaited(_restartDriver(st));
              },
              isRestarting: _restartingDriver,
            )
          : null,
      subToolbar: _filterActive
          ? material.Container(
              padding: const material.EdgeInsets.symmetric(
                  horizontal: 16, vertical: 8),
              decoration: material.BoxDecoration(
                color:
                    Theme.of(context).colorScheme.muted.withValues(alpha: 0.3),
                border: material.Border(
                  bottom: material.BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .border
                        .withValues(alpha: 0.3),
                  ),
                ),
              ),
              child: material.Row(
                children: [
                  const material.Text('WHERE ').semiBold().small(),
                  const Gap(8),
                  material.Expanded(
                    child: material.TextField(
                      controller: _filterController,
                      decoration: const material.InputDecoration(
                        hintText: "e.g. id > 100 AND status = 'active'",
                        isDense: true,
                        border: material.OutlineInputBorder(),
                      ),
                      onSubmitted: (_) {
                        final st = _genericKey.currentState;
                        if (st != null) _applyFilter(st);
                      },
                    ),
                  ),
                  const Gap(8),
                  OutlineButton(
                    size: ButtonSize.small,
                    onPressed: () {
                      final st = _genericKey.currentState;
                      if (st != null) _applyFilter(st);
                    },
                    child: const Text('Apply'),
                  ),
                  if (_filterController.text.isNotEmpty) ...[
                    const Gap(6),
                    GhostButton(
                      size: ButtonSize.small,
                      onPressed: () {
                        final st = _genericKey.currentState;
                        if (st != null) _clearFilter(st);
                      },
                      child: const Text('Clear'),
                    ),
                  ],
                ],
              ),
            )
          : null,
      customToolbarBuilder: (ctx, state) {
        return ExtensionTableToolbar(
          title: tableTitle,
          paginationLabel: state.statusLine() ?? 'Loading...',
          tableIcon: widget.isView
              ? material.Icons.view_list_rounded
              : material.Icons.table_chart_outlined,
          loading: state.isLoading,
          canGoPrevious: state.canGoPrevious,
          canGoNext: state.canGoNext,
          onNavigateHome: widget.onNavigateHome != null
              ? () => unawaited(state.navigateHome())
              : null,
          filterActive: _filterActive || _filterController.text.isNotEmpty,
          filterText: _filterController.text,
          onToggleFilter: () {
            setState(() {
              _filterActive = !_filterActive;
            });
          },
          onOpenDdl: () => unawaited(_openDdlDialog()),
          onGoPrevious: state.goToPreviousPage,
          onGoNext: state.goToNextPage,
          onRefresh: () => unawaited(state.refresh()),
          onRestartDriver: () => unawaited(_restartDriver(state)),
          isRestarting: _restartingDriver,
          editAction: widget.isView ? null : state.buildEditModeButton(),
          onCopyFormat: (format) {
            unawaited(() async {
              await DataExportService.copyToClipboard(
                format,
                columns: state.columnNames,
                rows: state.rows,
              );
            }());
          },
          onSaveFormat: (format) {
            unawaited(() async {
              final outcome = await DataExportService.saveToFile(
                format,
                columns: state.columnNames,
                rows: state.rows,
              );
              if (!ctx.mounted) return;
              if (outcome == SaveExportOutcome.error) {
                await _showSaveFileErrorDialog(ctx);
              }
            }());
          },
        );
      },
    );
  }
}

Future<void> _showSaveFileErrorDialog(material.BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => QueryaDialogCard(
      constraints: const material.BoxConstraints(maxWidth: 420),
      child: material.Padding(
        padding: const material.EdgeInsets.all(20),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            const Text('Could not save file').semiBold().large(),
            const Gap(8),
            const Text(
              'The file could not be saved. Please check folder permissions or disk space.',
            ).muted().small(),
            const Gap(20),
            material.Align(
              alignment: material.Alignment.centerRight,
              child: PrimaryButton(
                onPressed: () => material.Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
