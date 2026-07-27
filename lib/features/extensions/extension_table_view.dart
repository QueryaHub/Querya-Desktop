import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/extensions/extension_table_toolbar.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

const _defaultPageSize = 200;

/// Paginated data browser for extension driver tables and views with async count and toolbar.
class ExtensionTableView extends material.StatefulWidget {
  const ExtensionTableView({
    super.key,
    required this.connectionRow,
    required this.database,
    required this.tableName,
    this.isView = false,
    this.pageSize = _defaultPageSize,
  });

  final ConnectionRow connectionRow;
  final String database;
  final String tableName;
  final bool isView;
  final int pageSize;

  @override
  material.State<ExtensionTableView> createState() =>
      _ExtensionTableViewState();
}

class _ExtensionTableViewState extends material.State<ExtensionTableView> {
  bool _loading = true;
  String? _error;
  List<String> _columns = [];
  List<List<String>> _rows = [];
  int _offset = 0;
  int? _totalRows;
  String? _statusLine;

  bool _filterActive = false;
  final _filterController = material.TextEditingController();

  String get _qualifiedName => '`${widget.database}`.`${widget.tableName}`';

  String get _whereClause {
    final text = _filterController.text.trim();
    return text.isEmpty ? '' : ' WHERE $text';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadPage(refreshCount: true));
  }

  @override
  void didUpdateWidget(covariant ExtensionTableView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connectionRow.id != widget.connectionRow.id ||
        oldWidget.database != widget.database ||
        oldWidget.tableName != widget.tableName) {
      _offset = 0;
      _totalRows = null;
      _filterController.clear();
      _filterActive = false;
      unawaited(_loadPage(refreshCount: true));
    }
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  void _updateStatusLine() {
    final total = _totalRows;
    final shownFrom = _rows.isEmpty ? 0 : _offset + 1;
    final shownTo = _offset + _rows.length;
    if (total == null) {
      _statusLine = _loading
          ? 'Loading data...'
          : 'Showing $shownTo row(s) (Calculating count...).';
    } else {
      _statusLine = 'Rows $shownFrom–$shownTo of $total.';
    }
  }

  Future<void> _fetchCountAsync({required bool refresh}) async {
    if (!refresh && _totalRows != null) return;
    try {
      final countQuery =
          'SELECT count(*) AS cnt FROM $_qualifiedName$_whereClause';
      final countResult = await ExtensionDriverSession.instance.query(
        widget.connectionRow,
        countQuery,
      );
      if (countResult.rows.isNotEmpty && countResult.rows.first.isNotEmpty) {
        if (!mounted) return;
        setState(() {
          _totalRows = int.tryParse(countResult.rows.first.first);
          _updateStatusLine();
        });
        return;
      }
    } catch (_) {
      // Fallback for drivers that only support count() without asterisk
      try {
        final fallbackQuery =
            'SELECT count() AS cnt FROM $_qualifiedName$_whereClause';
        final countResult = await ExtensionDriverSession.instance.query(
          widget.connectionRow,
          fallbackQuery,
        );
        if (countResult.rows.isNotEmpty && countResult.rows.first.isNotEmpty) {
          if (!mounted) return;
          setState(() {
            _totalRows = int.tryParse(countResult.rows.first.first);
            _updateStatusLine();
          });
        }
      } catch (_) {
        // Ignore count errors on stream or schema tables that do not support count queries
      }
    }
  }

  Future<void> _loadPage({bool refreshCount = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      if (refreshCount) _totalRows = null;
      _updateStatusLine();
    });

    try {
      final dataResult = await ExtensionDriverSession.instance.query(
        widget.connectionRow,
        'SELECT * FROM $_qualifiedName$_whereClause LIMIT ${widget.pageSize} OFFSET $_offset',
      );

      if (!mounted) return;
      setState(() {
        _columns = dataResult.columns;
        _rows = dataResult.rows;
        _loading = false;
        _updateStatusLine();
      });

      unawaited(_fetchCountAsync(refresh: refreshCount || _totalRows == null));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _updateStatusLine();
      });
    }
  }

  void _applyFilter() {
    _offset = 0;
    _totalRows = null;
    unawaited(_loadPage(refreshCount: true));
  }

  void _clearFilter() {
    _filterController.clear();
    _offset = 0;
    _totalRows = null;
    unawaited(_loadPage(refreshCount: true));
  }

  Future<void> _openDdlDialog() async {
    final navigator = material.Navigator.of(context, rootNavigator: true);
    unawaited(showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const material.Center(
        child: material.CircularProgressIndicator(),
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
          : '-- No DDL metadata returned by extension driver for ${widget.tableName}\nSELECT * FROM $_qualifiedName LIMIT 10;';

      await showAppDialog<void>(
        context: context,
        builder: (ctx) => material.AlertDialog(
          title: material.Text(
              '${widget.isView ? "View" : "Table"} DDL · ${widget.tableName}'),
          content: material.SizedBox(
            width: 600,
            height: 400,
            child: material.SingleChildScrollView(
              child: material.SelectableText(
                ddlText,
                style: const material.TextStyle(
                    fontFamily: 'monospace', fontSize: 13),
              ),
            ),
          ),
          actions: [
            material.TextButton(
              onPressed: () => material.Navigator.of(ctx).pop(),
              child: const material.Text('Close'),
            ),
          ],
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

  bool get _canGoBack => _offset > 0;

  bool get _canGoForward {
    final total = _totalRows;
    if (total == null) return _rows.length >= widget.pageSize;
    return _offset + widget.pageSize < total;
  }

  void _previousPage() {
    if (!_canGoBack || _loading) return;
    _offset = (_offset - widget.pageSize).clamp(0, 1 << 30);
    unawaited(_loadPage());
  }

  void _nextPage() {
    if (!_canGoForward || _loading) return;
    _offset += widget.pageSize;
    unawaited(_loadPage());
  }

  @override
  material.Widget build(material.BuildContext context) {
    final kind = widget.isView ? 'View' : 'Table';

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        ExtensionTableToolbar(
          title: '$kind · ${widget.database}.${widget.tableName}',
          paginationLabel: _statusLine ?? 'Loading...',
          tableIcon: widget.isView
              ? material.Icons.view_list_rounded
              : material.Icons.table_chart_outlined,
          loading: _loading,
          canGoPrevious: _canGoBack && !_loading,
          canGoNext: _canGoForward && !_loading,
          filterActive: _filterActive || _filterController.text.isNotEmpty,
          filterText: _filterController.text,
          onToggleFilter: () {
            setState(() {
              _filterActive = !_filterActive;
            });
          },
          onOpenDdl: _openDdlDialog,
          onGoPrevious: _previousPage,
          onGoNext: _nextPage,
          onRefresh: () => _loadPage(refreshCount: true),
          onCopyFormat: (format) {
            unawaited(() async {
              await DataExportService.copyToClipboard(
                format,
                columns: _columns,
                rows: _rows,
              );
            }());
          },
          onSaveFormat: (format) {
            unawaited(() async {
              final outcome = await DataExportService.saveToFile(
                format,
                columns: _columns,
                rows: _rows,
              );
              if (!context.mounted) return;
              if (outcome == SaveExportOutcome.error) {
                await _showSaveFileErrorDialog(context);
              }
            }());
          },
        ),
        if (_filterActive)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
                horizontal: 16, vertical: 8),
            decoration: material.BoxDecoration(
              color: Theme.of(context).colorScheme.muted.withValues(alpha: 0.3),
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
                    onSubmitted: (_) => _applyFilter(),
                  ),
                ),
                const Gap(8),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: _applyFilter,
                  child: const Text('Apply'),
                ),
                if (_filterController.text.isNotEmpty) ...[
                  const Gap(6),
                  GhostButton(
                    size: ButtonSize.small,
                    onPressed: _clearFilter,
                    child: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ),
        material.Expanded(
          child: ResultsTab(
            columns: _columns,
            rows: _rows,
            errorMessage: _error,
            isLoading: _loading,
            statusLine: _statusLine,
            showExportToolbar: false,
          ),
        ),
      ],
    );
  }
}

Future<void> _showSaveFileErrorDialog(material.BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => material.AlertDialog(
      title: const material.Text('Could not save file'),
      content: const material.Text(
        'The file could not be saved. Please check folder permissions or disk space.',
      ),
      actions: [
        material.TextButton(
          onPressed: () => material.Navigator.of(ctx).pop(),
          child: const material.Text('OK'),
        ),
      ],
    ),
  );
}
