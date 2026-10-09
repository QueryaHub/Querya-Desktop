import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:querya_desktop/core/storage/local_db.dart' show MutationAuditSource;
import 'package:querya_desktop/core/storage/mutation_audit_recorder.dart';
import 'package:querya_desktop/core/actions/table_view_command_bridge.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/features/erd/erd_source.dart';
import 'package:querya_desktop/features/erd/erd_view.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/results_tab.dart';
import 'package:querya_desktop/features/workspace/table_data_delegate.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Reusable database table browser supporting:
/// - Pagination (LIMIT/OFFSET) and row counts
/// - In-place editing via [DataGridStagingBuffer] and transactional saving
/// - Custom SQL query execution / dialog
/// - Keyboard shortcuts (Ctrl/Cmd+E for edit mode, F5 for refresh)
/// - Flexible toolbar and custom sub-toolbars (e.g. filter bar)
class GenericTableView extends material.StatefulWidget {
  const GenericTableView({
    super.key,
    required this.delegate,
    required this.title,
    this.tableTitle,
    required this.dialect,
    this.tableName = '',
    this.schema,
    this.isView = false,
    this.isMaterializedView = false,
    this.isReadOnly = false,
    this.limit = 200,
    this.onNavigateHome,
    this.customToolbarBuilder,
    this.subToolbar,
    this.errorAction,
    this.showExportToolbar = true,
    this.showRelations = true,
    this.onOpenNeighbour,
    this.onOpenFullDiagram,
  });

  final TableDataMutationDelegate delegate;
  final String title;
  final String? tableTitle;
  final SqlDialect dialect;
  final String tableName;
  final String? schema;
  final bool isView;
  final bool isMaterializedView;
  final bool isReadOnly;
  final int limit;
  final material.VoidCallback? onNavigateHome;
  final material.Widget Function(material.BuildContext context, GenericTableViewState state)?
      customToolbarBuilder;
  final material.Widget? subToolbar;
  final material.Widget? errorAction;
  final bool showExportToolbar;

  /// Offers the Data | Relations switch. Extension tables have no diagram.
  final bool showRelations;

  /// Double click on a neighbour in the Relations view.
  final void Function(String table)? onOpenNeighbour;

  /// Opens the full diagram focused on this table.
  final void Function(String table)? onOpenFullDiagram;

  @override
  material.State<GenericTableView> createState() => GenericTableViewState();
}

class GenericTableViewState extends material.State<GenericTableView> {
  bool _loading = true;
  String? _error;

  List<String> _columnNames = [];
  List<List<String>> _rows = [];
  int _rowsOnPage = 0;
  int? _totalRowCount;
  int _offset = 0;

  bool _customSqlActive = false;
  String? _customSql;

  DataGridStagingBuffer? _stagingBuffer;
  List<String> _primaryKeys = [];
  Map<String, String> _columnDataTypes = {};
  Map<String, TableColumnMeta> _columnMeta = {};
  bool _schemaLoaded = false;
  Object? _schemaError;
  bool _isSaving = false;
  bool _editMode = false;

  bool get isLoading => _loading;

  bool _relationsMode = false;
  bool _relationsVisited = false;
  int _relationsDepth = 1;

  bool get showsRelations =>
      widget.showRelations && !widget.isView && !widget.isMaterializedView;

  /// Neighbourhood source over this table's own read-only session.
  ErdSource get _erdSource => SqlErdSource(
        delegate: TableDataSqlAdapter(widget.delegate),
        dialect: widget.dialect,
      );

  /// Data | Relations, for tables with a diagram source.
  material.Widget buildViewSwitch() {
    if (!showsRelations) return const material.SizedBox.shrink();
    return QueryaTabStrip(
      labels: const ['Data', 'Relations'],
      selectedIndex: _relationsMode ? 1 : 0,
      onSelected: selectView,
    );
  }

  /// 0 shows the grid (Data), 1 the neighbourhood (Relations).
  void selectView(int index) {
    setState(() {
      _relationsMode = index == 1;
      if (_relationsMode) _relationsVisited = true;
    });
  }

  /// Neighbourhood of this table. Built on the first switch and kept, so
  /// the grid's state (staged edits, page, filter) is never disturbed.
  material.Widget _buildRelations() {
    final schema = widget.schema;
    final focus = schema == null || schema.isEmpty
        ? widget.tableName
        : '$schema.${widget.tableName}';
    void openFull() => widget.onOpenFullDiagram?.call(focus);
    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        material.Padding(
          padding: const material.EdgeInsets.all(8),
          child: material.Row(
            children: [
              for (final d in const [1, 2])
                QueryaActionButton(
                  key: material.ValueKey('relations_depth_$d'),
                  label: 'Depth $d',
                  onPressed: () => setState(() => _relationsDepth = d),
                ),
              const material.Spacer(),
              QueryaActionButton(
                key: const material.ValueKey('relations_open_diagram'),
                label: 'Open full diagram',
                onPressed: widget.onOpenFullDiagram == null ? null : openFull,
              ),
            ],
          ),
        ),
        material.Expanded(
          child: ErdView(
            key: material.ValueKey('relations_${focus}_$_relationsDepth'),
            source: _erdSource,
            focusTable: focus,
            neighbourhoodDepth: _relationsDepth,
            onOpenTable: widget.onOpenNeighbour,
            onOpenFullDiagram:
                widget.onOpenFullDiagram == null ? null : openFull,
          ),
        ),
      ],
    );
  }
  String? get error => _error;
  List<String> get columnNames => _columnNames;
  List<List<String>> get rows => _rows;
  int get rowsOnPage => _rowsOnPage;
  int? get totalRowCount => _totalRowCount;
  int get offset => _offset;
  bool get customSqlActive => _customSqlActive;
  String? get customSql => _customSql;
  DataGridStagingBuffer? get stagingBuffer => _stagingBuffer;
  bool get isSaving => _isSaving;
  bool get editMode => _editMode;
  bool get isDirty => _stagingBuffer?.isDirty ?? false;

  String get effectiveTableTitle =>
      widget.tableTitle ?? widget.title;

  bool get canEdit => tableViewEditingEnabled(
        isView: widget.isView,
        isMaterializedView: widget.isMaterializedView,
        customSqlActive: _customSqlActive,
        hasPrimaryKey: _primaryKeys.isNotEmpty,
        readOnly: widget.isReadOnly,
        schemaError: _schemaError,
      );

  bool get editingEnabled => canEdit && _editMode;

  bool get canGoPrevious =>
      !_customSqlActive && _offset > 0 && !_loading && !isDirty;

  bool get canGoNext {
    if (_customSqlActive || _loading || isDirty) return false;
    final total = _totalRowCount;
    final limit = widget.limit;
    if (total != null) {
      return _offset + _rowsOnPage < total;
    }
    return _rowsOnPage >= limit;
  }

  @override
  void initState() {
    super.initState();
    _loadPage(refreshCount: true);
    _syncRelationsCommand();
  }

  /// The Command Palette can switch Data / Relations only while this table
  /// offers the switch.
  void _syncRelationsCommand() {
    final bridge = TableViewCommandBridge.instance;
    if (showsRelations) {
      bridge.register(owner: this, onSelectView: selectView);
    } else {
      bridge.unregister(owner: this);
    }
  }

  @override
  void didUpdateWidget(covariant GenericTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delegate != widget.delegate ||
        oldWidget.tableName != widget.tableName ||
        oldWidget.schema != widget.schema ||
        oldWidget.isView != widget.isView ||
        oldWidget.isMaterializedView != widget.isMaterializedView) {
      _customSqlActive = false;
      _customSql = null;
      _resetStaging();
      _offset = 0;
      _loadPage(refreshCount: true);
    } else if (oldWidget.isReadOnly != widget.isReadOnly) {
      _syncStagingToReadOnly();
    }
    _syncRelationsCommand();
  }

  @override
  void dispose() {
    TableViewCommandBridge.instance.unregister(owner: this);
    _resetStaging();
    widget.delegate.cancel(interruptIfBusy: true);
    widget.delegate.dispose();
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
    if (widget.isReadOnly) {
      _stagingBuffer?.dispose();
      _stagingBuffer = null;
    } else if (_columnNames.isNotEmpty) {
      _stagingBuffer = replaceTableViewStagingBuffer(
        previous: _stagingBuffer,
        columns: _columnNames,
        rows: _rows,
        enabled: editingEnabled,
        primaryKeys: _primaryKeys,
      );
    }
    if (mounted) setState(() {});
  }

  Future<void> _ensureSchema() async {
    if (_schemaLoaded) return;
    if (widget.isView || widget.isMaterializedView || widget.isReadOnly) {
      _schemaLoaded = true;
      _schemaError = null;
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
      return;
    }

    try {
      final info = await widget.delegate.loadSchema();
      _primaryKeys = List<String>.from(info.primaryKeys);
      _columnDataTypes = Map<String, String>.from(info.columnDataTypes);
      _columnMeta = Map<String, TableColumnMeta>.from(info.columnMeta);
      _schemaError = info.schemaError;
    } catch (e) {
      _primaryKeys = [];
      _columnDataTypes = {};
      _columnMeta = {};
      _schemaError = e;
    }
    _schemaLoaded = true;
  }

  void _installStagingBuffer(List<String> columns, List<List<String>> rows) {
    _stagingBuffer = replaceTableViewStagingBuffer(
      previous: _stagingBuffer,
      columns: columns,
      rows: rows,
      enabled: editingEnabled,
      primaryKeys: _primaryKeys,
    );
  }

  Future<void> _loadPage({bool refreshCount = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (refreshCount) _totalRowCount = null;
    });

    try {
      await _ensureSchema();
      if (!mounted) return;

      final page = await widget.delegate.loadPage(
        offset: _offset,
        limit: widget.limit,
        refreshCount: refreshCount,
      );

      if (!mounted) return;
      final shown = page.rows.length;
      var totalRows = page.totalRowCount ?? _totalRowCount;
      if (totalRows != null && shown > 0 && totalRows < _offset + shown) {
        totalRows = null;
      }

      setState(() {
        _columnNames = page.columns;
        _rows = page.rows;
        _rowsOnPage = shown;
        _totalRowCount = totalRows;
        _loading = false;
        _installStagingBuffer(page.columns, page.rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _fetchCustom() async {
    final sql = _customSql;
    if (sql == null || sql.isEmpty) return;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final page = await widget.delegate.loadCustomSql(sql);
      if (!mounted) return;
      setState(() {
        _columnNames = page.columns;
        _rows = page.rows;
        _rowsOnPage = page.rows.length;
        _totalRowCount = null;
        _loading = false;
        _installStagingBuffer(page.columns, page.rows);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<bool> confirmDiscardIfNeeded() {
    return confirmDiscardTableEditsIfDirty(
      context: context,
      buffer: _stagingBuffer,
      tableTitle: effectiveTableTitle,
    );
  }

  String? editDisabledReason() => tableViewEditDisabledReason(
        isView: widget.isView,
        isMaterializedView: widget.isMaterializedView,
        customSqlActive: _customSqlActive,
        hasPrimaryKey: _primaryKeys.isNotEmpty,
        schemaLoaded: _schemaLoaded,
        readOnly: widget.isReadOnly,
        schemaError: _schemaError,
      );

  void enterEditMode() {
    if (!canEdit || _editMode) return;
    setState(() {
      _editMode = true;
      _stagingBuffer = replaceTableViewStagingBuffer(
        previous: _stagingBuffer,
        columns: _columnNames,
        rows: _rows,
        enabled: editingEnabled,
        primaryKeys: _primaryKeys,
      );
    });
  }

  Future<void> exitEditMode() async {
    if (!_editMode) return;
    if (!await confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _editMode = false;
      _stagingBuffer?.dispose();
      _stagingBuffer = null;
    });
  }

  void toggleEditMode() {
    if (_editMode) {
      unawaited(exitEditMode());
    } else {
      enterEditMode();
    }
  }

  material.Widget buildEditModeButton() => TableEditModeButton(
        editMode: _editMode,
        canEdit: canEdit,
        busy: _loading || _isSaving,
        disabledReason: editDisabledReason(),
        onEdit: enterEditMode,
        onDone: () => unawaited(exitEditMode()),
      );

  void goToPreviousPage() {
    if (_customSqlActive) return;
    if (_offset <= 0 || _loading || isDirty) return;
    setState(() {
      final next = _offset - widget.limit;
      _offset = next < 0 ? 0 : next;
    });
    unawaited(_loadPage());
  }

  void goToNextPage() {
    if (_customSqlActive) return;
    if (_loading || isDirty) return;
    final total = _totalRowCount;
    final limit = widget.limit;
    if (total != null && _offset + _rowsOnPage >= total) return;
    if (total == null && _rowsOnPage < limit) return;
    setState(() {
      _offset += limit;
    });
    unawaited(_loadPage());
  }

  String paginationLabel() {
    if (_customSqlActive) {
      if (_rowsOnPage == 0) return '0 rows (custom SQL)';
      return '$_rowsOnPage row${_rowsOnPage == 1 ? '' : 's'} (custom SQL)';
    }
    if (_rowsOnPage == 0) {
      final t = _totalRowCount;
      if (t == null) return '0 rows';
      return '0 of $t';
    }
    final start = _offset + 1;
    final end = _offset + _rowsOnPage;
    final total = _totalRowCount;
    if (total != null) {
      return '$start–$end of $total';
    }
    return '$start–$end';
  }

  String? statusLine() {
    final reason = editDisabledReason();
    final pag = paginationLabel();
    if (reason != null) return '$pag · $reason';
    return pag;
  }

  Future<void> refresh() async {
    if (!await confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    _schemaLoaded = false;
    _schemaError = null;
    if (_customSqlActive) {
      await _fetchCustom();
    } else {
      await _loadPage(refreshCount: true);
    }
  }

  Future<void> exitCustomMode() async {
    if (!await confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    setState(() {
      _customSqlActive = false;
      _customSql = null;
    });
    await _loadPage(refreshCount: true);
  }

  Future<void> runCustomSql(String sql) async {
    final trimmed = sql.trim();
    if (!widget.delegate.isAllowedSelectQuery(trimmed)) return;
    if (!await confirmDiscardIfNeeded()) return;
    if (!mounted) return;

    final browse = widget.delegate.browseDataSql(
      offset: _offset,
      limit: widget.limit,
    ).trim();

    if (_browseSqlCompareKey(trimmed) == _browseSqlCompareKey(browse)) {
      setState(() {
        _customSqlActive = false;
        _customSql = null;
      });
      await _loadPage(refreshCount: true);
    } else {
      setState(() {
        _customSqlActive = true;
        _customSql = trimmed;
      });
      await _fetchCustom();
    }
  }

  String browseDataSql() => widget.delegate.browseDataSql(
        offset: _offset,
        limit: widget.limit,
      );

  Future<void> navigateHome() async {
    final home = widget.onNavigateHome;
    if (home == null) return;
    if (!await confirmDiscardIfNeeded()) return;
    if (!mounted) return;
    home();
  }

  Future<void> applyStagedChanges() async {
    if (widget.isReadOnly) return;
    final buffer = _stagingBuffer;
    if (buffer == null || !buffer.isDirty || _isSaving) return;
    setState(() => _isSaving = true);

    final outcome = await applyTableViewStagedChanges(
      context: context,
      buffer: buffer,
      dialect: widget.dialect,
      tableName: widget.tableName,
      schema: widget.schema,
      primaryKeys: _primaryKeys,
      columnDataTypes: _columnDataTypes.isEmpty ? null : _columnDataTypes,
      columnMeta: _columnMeta.isEmpty ? null : _columnMeta,
      execute: (plan) async {
        await widget.delegate.applyStagedChanges(
          plan: plan,
          buffer: buffer,
        );
        auditMutationPlan(
          connection: widget.delegate.auditConnection,
          databaseName: widget.delegate.auditDatabaseName,
          plan: plan,
          source: MutationAuditSource.tableEditor,
        );
      },
    );

    if (!mounted) return;
    if (outcome.isApplied) {
      if (buffer.insertedRowCount > 0) {
        buffer.dispose();
        setState(() {
          _stagingBuffer = null;
          _isSaving = false;
        });
        showAppToast(
          context: context,
          message: tableViewSavedMessage(outcome.statementCount),
          variant: AppToastVariant.success,
        );
        await _loadPage(refreshCount: true);
        return;
      }
      final newRows = buffer.committedRows;
      buffer.dispose();
      setState(() {
        _rows = newRows;
        _rowsOnPage = newRows.length;
        _stagingBuffer = replaceTableViewStagingBuffer(
          previous: null,
          columns: _columnNames,
          rows: newRows,
          enabled: editingEnabled,
          primaryKeys: _primaryKeys,
        );
        _isSaving = false;
      });
      showAppToast(
        context: context,
        message: tableViewSavedMessage(outcome.statementCount),
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

  material.Widget _buildDefaultToolbar() {
    final cs = Theme.of(context).colorScheme;
    final title = '$effectiveTableTitle${widget.isMaterializedView ? ' (materialized view)' : widget.isView ? ' (view)' : ''}';

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
                onPressed: () => unawaited(navigateHome()),
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
            widget.isMaterializedView
                ? material.Icons.dynamic_feed_rounded
                : widget.isView
                    ? material.Icons.view_agenda_rounded
                    : material.Icons.table_chart_rounded,
            size: 18,
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
                            paginationLabel(),
                            style: material.TextStyle(
                              fontSize: 11,
                              color: cs.mutedForeground,
                            ),
                          ),
                        ),
                        const Gap(6),
                        if (!widget.isView && !widget.isMaterializedView) ...[
                          buildViewSwitch(),
                          buildEditModeButton(),
                          const Gap(4),
                        ],
                        if (_customSqlActive) ...[
                          OutlineButton(
                            size: ButtonSize.small,
                            onPressed: _loading ? null : () => unawaited(exitCustomMode()),
                            leading: const material.Icon(
                              material.Icons.table_chart_rounded,
                              size: 15,
                            ),
                            child: const Text('Browse'),
                          ),
                          const Gap(4),
                        ],
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: (!canGoPrevious || _loading) ? null : goToPreviousPage,
                          leading: const material.Icon(
                            material.Icons.chevron_left_rounded,
                            size: 16,
                          ),
                          child: const Text('Prev'),
                        ),
                        const Gap(4),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: (!canGoNext || _loading) ? null : goToNextPage,
                          leading: const material.Icon(
                            material.Icons.chevron_right_rounded,
                            size: 16,
                          ),
                          child: const Text('Next'),
                        ),
                        const Gap(8),
                        OutlineButton(
                          size: ButtonSize.small,
                          onPressed: _loading ? null : () => unawaited(refresh()),
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
  }

  @override
  material.Widget build(material.BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final buffer = _stagingBuffer;

    final toolbar = widget.customToolbarBuilder != null
        ? widget.customToolbarBuilder!(context, this)
        : _buildDefaultToolbar();

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.keyE, control: true):
            toggleEditMode,
        const material.SingleActivator(LogicalKeyboardKey.keyE, meta: true):
            toggleEditMode,
        const material.SingleActivator(LogicalKeyboardKey.f5): () {
          if (!_loading) unawaited(refresh());
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
                toolbar
              else
                ListenableBuilder(
                  listenable: buffer,
                  builder: (context, _) => toolbar,
                ),
              if (widget.subToolbar != null) widget.subToolbar!,
              material.Expanded(
                child: material.IndexedStack(
                  index: _relationsMode ? 1 : 0,
                  children: [
                ResultsTab(
                  columns: _columnNames,
                  rows: _rows,
                  errorMessage: _error,
                  isLoading: _loading,
                  statusLine: statusLine(),
                  showExportToolbar: widget.showExportToolbar,
                  stagingBuffer: _stagingBuffer,
                  columnDataTypes:
                      _columnDataTypes.isEmpty ? null : _columnDataTypes,
                  onApplyChanges:
                      _stagingBuffer != null ? applyStagedChanges : null,
                  isSaving: _isSaving,
                  errorAction: widget.errorAction,
                ),
                  if (_relationsVisited)
                    _buildRelations()
                  else
                    const material.SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _browseSqlCompareKey(String sql) {
    var s = sql.trim();
    while (s.endsWith(';')) {
      s = s.substring(0, s.length - 1).trimRight();
    }
    return s.replaceAll(RegExp(r'\s+'), ' ');
  }
}
