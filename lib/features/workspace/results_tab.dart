import 'dart:async' show Timer, unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/security/pii_masking_controller.dart';
import 'package:querya_desktop/core/actions/data_grid_command_bridge.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
import 'package:querya_desktop/features/results/charts/quick_chart_view.dart';
import 'package:querya_desktop/features/workspace/data_grid_calc_bar.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';
import 'package:querya_desktop/features/workspace/data_grid_groupings_view.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_toolbar.dart';
import 'package:querya_desktop/features/workspace/data_grid_value_panel.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';
import 'package:querya_desktop/features/workspace/grid_selection_calc_engine.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

enum ResultViewMode {
  grid,
  groupings,
  charts,
}

/// Query output: grid, loading, error, or placeholder.
/// Pause after the last selection change before aggregates are recomputed.
const kSelectionStatsDebounce = Duration(milliseconds: 60);

/// The cell that has keyboard focus, shown in the value inspector panel.
@immutable
class _FocusedCell {
  const _FocusedCell({
    required this.columnName,
    required this.value,
    required this.rowIndex,
  });

  final String columnName;
  final String value;
  final int? rowIndex;
}

class ResultsTab extends material.StatefulWidget {
  const ResultsTab({
    super.key,
    this.columns = const [],
    this.rows = const [],
    this.errorMessage,
    this.isLoading = false,
    this.affectedRows,
    this.statusLine,
    this.elapsed,
    this.showExportToolbar = true,
    this.stagingBuffer,
    this.onApplyChanges,
    this.isSaving = false,
    this.errorAction,
    this.columnDataTypes,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? errorMessage;
  final bool isLoading;
  final int? affectedRows;
  final String? statusLine;

  /// Time the query took, shown as a badge next to the row count.
  final Duration? elapsed;
  final bool showExportToolbar;
  final DataGridStagingBuffer? stagingBuffer;
  final material.VoidCallback? onApplyChanges;
  final bool isSaving;
  final material.Widget? errorAction;

  /// Column name → SQL type for cell hover tooltips and the inline editor.
  final Map<String, String>? columnDataTypes;

  @override
  material.State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends material.State<ResultsTab> {
  /// Selection / focus state lives in notifiers so a navigation step rebuilds
  /// only the widgets that show it (toolbar, value panel, calc bar), not the
  /// whole tab and its grid.
  final _selectedRowIndex = material.ValueNotifier<int?>(null);
  final _focusedCell = material.ValueNotifier<_FocusedCell?>(null);
  final _selectionStats =
      material.ValueNotifier<GridCalcStats>(GridCalcStats.empty);
  Timer? _statsDebounce;

  /// Bumped for every selection change; a stats result is applied only if it
  /// still matches, so a slow older aggregation cannot overwrite a newer one.
  int _statsSeq = 0;

  ResultViewMode _viewMode = ResultViewMode.grid;

  bool _showFilterBar = false;
  String _filterText = '';

  bool _showValuePanel = false;

  String? _memoFilterText;
  List<String>? _memoColumns;
  List<List<String>>? _memoEffectiveRows;
  List<List<String>> _cachedFilteredRows = const [];
  List<int>? _cachedFilteredIndices;

  List<List<String>> _getFilteredRows(
    List<List<String>> effectiveRows,
    List<String> columns,
  ) {
    if (_memoFilterText == _filterText &&
        identical(_memoEffectiveRows, effectiveRows) &&
        identical(_memoColumns, columns)) {
      return _cachedFilteredRows;
    }

    final filteredIndices = GridFilterEngine.filterRowIndices(
      filterText: _filterText,
      columns: columns,
      rows: effectiveRows,
    );

    final isFiltered = filteredIndices.length != effectiveRows.length;
    final filteredRows = !isFiltered
        ? effectiveRows
        : filteredIndices.map((i) => effectiveRows[i]).toList();

    _memoFilterText = _filterText;
    _memoEffectiveRows = effectiveRows;
    _memoColumns = columns;
    _cachedFilteredRows = filteredRows;
    _cachedFilteredIndices = isFiltered ? filteredIndices : null;

    return filteredRows;
  }

  @override
  void initState() {
    super.initState();
    _syncGridBridge();
  }

  @override
  void didUpdateWidget(covariant ResultsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncGridBridge();
  }

  void _syncGridBridge() {
    final hasGrid = widget.showExportToolbar &&
        widget.columns.isNotEmpty &&
        widget.errorMessage == null &&
        !widget.isLoading;
    if (!hasGrid) {
      DataGridCommandBridge.instance.unregister();
      return;
    }
    final effectiveRows = widget.stagingBuffer != null
        ? widget.stagingBuffer!.effectiveRows
        : widget.rows;
    DataGridCommandBridge.instance.register(
      onToggleFilter: () {
        if (!mounted) return;
        setState(() => _showFilterBar = !_showFilterBar);
      },
      onToggleInspector: () {
        if (!mounted) return;
        setState(() => _showValuePanel = !_showValuePanel);
      },
      onCopy: (format) => unawaited(_copyAs(format)),
      onSaveExport: () => unawaited(_saveExport()),
      onApplyStaged: widget.onApplyChanges,
      canApplyStaged: () =>
          widget.stagingBuffer?.isDirty == true && !widget.isSaving,
      hasRows: effectiveRows.isNotEmpty,
    );
  }

  List<List<String>> _exportRows() {
    final effectiveRows = widget.stagingBuffer != null
        ? widget.stagingBuffer!.effectiveRows
        : widget.rows;
    return _getFilteredRows(effectiveRows, widget.columns);
  }

  Future<void> _copyAs(DataExportFormat format) async {
    final rows = _exportRows();
    await DataExportService.copyToClipboard(
      format,
      columns: widget.columns,
      rows: rows,
    );
    if (!mounted) return;
    showAppToast(
      context: context,
      message: 'Copied ${rows.length} rows as ${format.name.toUpperCase()}',
      variant: AppToastVariant.success,
    );
  }

  Future<void> _saveExport() async {
    final rows = _exportRows();
    final outcome = await DataExportService.saveToFile(
      DataExportFormat.csv,
      columns: widget.columns,
      rows: rows,
    );
    if (!mounted) return;
    if (outcome == SaveExportOutcome.written) {
      showAppToast(
        context: context,
        message: 'Exported ${rows.length} rows',
        variant: AppToastVariant.success,
      );
    } else if (outcome == SaveExportOutcome.error) {
      await _showSaveFileErrorDialog(context);
    }
  }

  /// Selection aggregates are recomputed after a short pause, so holding an
  /// arrow key or dragging a selection does not run the maths on every step.
  void _onSelectionValues(List<String> values) {
    final seq = ++_statsSeq;
    _statsDebounce?.cancel();
    if (values.isEmpty) {
      _selectionStats.value = GridCalcStats.empty;
      return;
    }
    _statsDebounce = Timer(kSelectionStatsDebounce, () {
      if (values.length < GridSelectionCalcEngine.computeThreshold) {
        _selectionStats.value = GridSelectionCalcEngine.compute(values);
        return;
      }
      unawaited(
        GridSelectionCalcEngine.computeAdaptive(values).then((stats) {
          if (mounted && seq == _statsSeq) _selectionStats.value = stats;
        }),
      );
    });
  }

  @override
  void dispose() {
    _statsDebounce?.cancel();
    _statsSeq++;
    _selectedRowIndex.dispose();
    _focusedCell.dispose();
    _selectionStats.dispose();
    DataGridCommandBridge.instance.unregister();
    _memoColumns = null;
    _memoEffectiveRows = null;
    _cachedFilteredRows = const [];
    _cachedFilteredIndices = null;
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (widget.isLoading) {
      return const material.Center(
        key: material.ValueKey('results_mode_loading'),
        child: QueryaSpinner(
          size: QueryaSpinnerSize.sm,
          label: 'Executing query...',
        ),
      );
    }

    if (widget.errorMessage != null) {
      return material.Center(
        key: const material.ValueKey('results_mode_error'),
        child: material.Padding(
          padding: const material.EdgeInsets.all(32),
          child: material.Column(
            mainAxisAlignment: material.MainAxisAlignment.center,
            children: [
              material.Icon(
                material.Icons.error_outline_rounded,
                size: 48,
                color: Theme.of(context).colorScheme.destructive,
              ),
              const Gap(16),
              const Text('Query Error').large().semiBold(),
              const Gap(8),
              VirtualSelectableTextView(
                text: widget.errorMessage!,
                style: material.TextStyle(
                  color: Theme.of(context).colorScheme.mutedForeground,
                  fontSize: 13,
                ),
              ),
              if (widget.errorAction != null) ...[
                const Gap(16),
                widget.errorAction!,
              ],
            ],
          ),
        ),
      );
    }

    if (widget.columns.isEmpty && widget.rows.isEmpty && widget.stagingBuffer == null) {
      if (widget.statusLine != null) {
        return material.Padding(
          key: const material.ValueKey('results_mode_status'),
          padding: const material.EdgeInsets.all(16),
          child: Align(
            alignment: material.Alignment.topLeft,
            child: Text(widget.statusLine!).muted().small(),
          ),
        );
      }
      if (widget.affectedRows != null) {
        return material.Center(
          key: const material.ValueKey('results_mode_affected'),
          child: Text('Rows affected: ${widget.affectedRows}').muted(),
        );
      }
      return material.Center(
        key: const material.ValueKey('results_mode_idle'),
        child: const Text('Run a query to see results here.').muted(),
      );
    }

    final effectiveRows = widget.stagingBuffer != null
        ? widget.stagingBuffer!.effectiveRows
        : widget.rows;

    final filteredRows = _getFilteredRows(effectiveRows, widget.columns);

    return material.CallbackShortcuts(
      bindings: {
        const material.SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            setState(() => _showFilterBar = !_showFilterBar),
        const material.SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            setState(() => _showFilterBar = !_showFilterBar),
        const material.SingleActivator(LogicalKeyboardKey.keyS, meta: true): () {
          if (widget.stagingBuffer?.isDirty == true && !widget.isSaving) {
            widget.onApplyChanges?.call();
          }
        },
        const material.SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (widget.stagingBuffer?.isDirty == true && !widget.isSaving) {
            widget.onApplyChanges?.call();
          }
        },
        const material.SingleActivator(LogicalKeyboardKey.keyG, meta: true): () =>
            setState(() {
          _viewMode = _viewMode == ResultViewMode.grid
              ? ResultViewMode.groupings
              : ResultViewMode.grid;
        }),
        const material.SingleActivator(LogicalKeyboardKey.keyG, control: true): () =>
            setState(() {
          _viewMode = _viewMode == ResultViewMode.grid
              ? ResultViewMode.groupings
              : ResultViewMode.grid;
        }),
      },
      child: material.Column(
        key: const material.ValueKey('results_mode_grid'),
        crossAxisAlignment: material.CrossAxisAlignment.stretch,
        children: [
          QueryaAnimatedExpand(
            expanded: widget.stagingBuffer != null,
            child: widget.stagingBuffer != null
                ? material.ValueListenableBuilder<int?>(
                    valueListenable: _selectedRowIndex,
                    builder: (_, selectedRow, __) => DataGridStagingToolbar(
                      stagingBuffer: widget.stagingBuffer!,
                      selectedRowIndex: selectedRow,
                      onApplyChanges: widget.onApplyChanges,
                      isSaving: widget.isSaving,
                    ),
                  )
                : const material.SizedBox.shrink(),
          ),
          QueryaAnimatedExpand(
            expanded: widget.showExportToolbar && widget.columns.isNotEmpty,
            child: material.Container(
              padding: const material.EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 4,
              ),
              decoration: material.BoxDecoration(
                color: Theme.of(context).colorScheme.card,
                border: material.Border(
                  bottom: material.BorderSide(
                    color: Theme.of(context)
                        .colorScheme
                        .border
                        .withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: material.SingleChildScrollView(
                scrollDirection: material.Axis.horizontal,
                child: material.Row(
                  mainAxisSize: material.MainAxisSize.min,
                  children: [
                    // Grid / Groupings View Selector
                    // Sized by its labels: a fixed box clipped the tabs and
                    // let "Groupings" run into its neighbours at larger UI
                    // scales.
                    QueryaTabStrip(
                      dense: true,
                      labels: const ['Grid', 'Groupings', 'Charts'],
                      selectedIndex: ResultViewMode.values.indexOf(_viewMode),
                      onSelected: (i) =>
                          setState(() => _viewMode = ResultViewMode.values[i]),
                    ),
                    const Gap(10),
                    Text(
                      widget.statusLine ??
                          (widget.affectedRows != null
                              ? 'Rows affected: ${widget.affectedRows}'
                              : '${filteredRows.length}${_filterText.isNotEmpty ? ' of ${effectiveRows.length}' : ''} rows'),
                    ).small().semiBold(),
                    if (widget.elapsed != null) ...[
                      const Gap(8),
                      QueryaBadge(
                        key: const material.ValueKey('result_elapsed'),
                        label: formatResultElapsed(widget.elapsed!),
                        isMonospace: true,
                      ),
                    ],

                    const Gap(16),

                    // Toggle Quick Filter
                    QueryaIconButton(
 density: QueryaIconButtonDensity.dense,
                      icon: material.Icon(
                        _showFilterBar ? material.Icons.filter_alt : material.Icons.filter_alt_outlined,
                        size: 15,
                      ),
                      tooltip: 'Toggle Quick Filter',
                      color: _showFilterBar || _filterText.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.mutedForeground,
                      onPressed: () {
                        setState(() => _showFilterBar = !_showFilterBar);
                      },
                    ),
                    const Gap(4),

                    // Mask sensitive data (passwords, tokens, emails, phones, cards)
                    material.ListenableBuilder(
                      listenable: PiiMaskingController.instance,
                      builder: (context, _) {
                        final masked = PiiMaskingController.instance.enabled;
                        return QueryaIconButton(
 density: QueryaIconButtonDensity.dense,
                          key: const material.Key(
                              'results_mask_sensitive_toggle'),
                          icon: material.Icon(
                            masked
                                ? material.Icons.visibility_off_rounded
                                : material.Icons.visibility_outlined,
                            size: 15,
                          ),
                          tooltip: masked
                              ? 'Sensitive data is masked — click to show'
                              : 'Mask sensitive data',
                          color: masked
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.mutedForeground,
                          onPressed: PiiMaskingController.instance.toggle,
                        );
                      },
                    ),
                    const Gap(4),

                    // Toggle Value Side Panel
                    QueryaIconButton(
 density: QueryaIconButtonDensity.dense,
                      icon: material.Icon(
                        _showValuePanel ? material.Icons.dock : material.Icons.data_object_rounded,
                        size: 15,
                      ),
                      tooltip: 'Inspect Cell Panel',
                      color: _showValuePanel
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.mutedForeground,
                      onPressed: () {
                        setState(() => _showValuePanel = !_showValuePanel);
                      },
                    ),
                    const Gap(8),

                    ExportMenuButton(
                      label: 'Export ▾',
                      icon: material.Icons.copy_rounded,
                      isSave: false,
                      onSelected: (format) => unawaited(_copyAs(format)),
                    ),
                    const Gap(6),
                    ExportMenuButton(
                      label: 'Save File ▾',
                      icon: material.Icons.download_rounded,
                      isSave: true,
                      onSelected: (format) {
                        unawaited(() async {
                          final rows = _exportRows();
                          final outcome = await DataExportService.saveToFile(
                            format,
                            columns: widget.columns,
                            rows: rows,
                          );
                          if (context.mounted) {
                            if (outcome == SaveExportOutcome.written) {
                              showAppToast(
                                context: context,
                                message: 'Exported ${rows.length} rows',
                                variant: AppToastVariant.success,
                              );
                            } else if (outcome == SaveExportOutcome.error) {
                              await _showSaveFileErrorDialog(context);
                            }
                          }
                        }());
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

        // Quick Filter Bar
        QueryaAnimatedExpand(
          expanded: _showFilterBar || _filterText.isNotEmpty,
          child: DataGridFilterBar(
            filterText: _filterText,
            onFilterChanged: (text) => setState(() => _filterText = text),
            totalRowCount: effectiveRows.length,
            filteredRowCount: filteredRows.length,
            columns: widget.columns,
            onClose: () => setState(() {
              _showFilterBar = false;
              _filterText = '';
            }),
          ),
        ),

        // Main Grid Body / Groupings View + Side Panel
        material.Expanded(
          child: QueryaFadeSlide(
            key: material.ValueKey(_viewMode),
            child: _viewMode == ResultViewMode.charts
                ? QuickChartView(
                    columns: widget.columns,
                    rows: filteredRows,
                  )
                : _viewMode == ResultViewMode.groupings
                ? DataGridGroupingsView(
                    columns: widget.columns,
                    rows: filteredRows,
                  )
                : material.Row(
                    crossAxisAlignment: material.CrossAxisAlignment.stretch,
                    children: [
                      material.Expanded(
                        child: VirtualResultGrid(
                          columns: widget.columns,
                          rows: filteredRows,
                          stagingBuffer: widget.stagingBuffer,
                          columnDataTypes: widget.columnDataTypes,
                          rowIndicesMapping: _cachedFilteredIndices,
                          onRowSelected: (row) => _selectedRowIndex.value = row,
                          onSelectionValuesChanged: _onSelectionValues,
                          onCellFocused: (colName, cellVal, rowIdx) {
                            _focusedCell.value = _FocusedCell(
                              columnName: colName,
                              value: cellVal,
                              rowIndex: rowIdx,
                            );
                          },
                          onFilterRequested: (filterExpr) {
                            setState(() {
                              _showFilterBar = true;
                              if (_filterText.trim().isEmpty) {
                                _filterText = filterExpr;
                              } else if (_filterText.contains(' OR ') || _filterText.contains(' or ')) {
                                _filterText = '($_filterText) AND $filterExpr';
                              } else {
                                _filterText = '$_filterText AND $filterExpr';
                              }
                            });
                          },
                        ),
                      ),

                      // Value Inspector Panel
                      material.ValueListenableBuilder<_FocusedCell?>(
                        valueListenable: _focusedCell,
                        builder: (context, focused, _) => material.AnimatedSize(
                          duration:
                              context.motionDuration(QueryaMotion.standard),
                          curve: context.motionCurve(QueryaMotion.enter),
                          alignment: material.Alignment.centerRight,
                          child: (_showValuePanel && focused != null)
                              ? DataGridValuePanel(
                                  columnName: focused.columnName,
                                  cellValue: focused.value,
                                  rowIndex: focused.rowIndex,
                                  onClose: () =>
                                      setState(() => _showValuePanel = false),
                                  onUpdateValue: widget.stagingBuffer != null &&
                                          focused.rowIndex != null
                                      ? (newVal) {
                                          final colIdx = widget.columns
                                              .indexOf(focused.columnName);
                                          if (colIdx != -1) {
                                            widget.stagingBuffer!.setCell(
                                              focused.rowIndex!,
                                              colIdx,
                                              newVal,
                                            );
                                          }
                                        }
                                      : null,
                                )
                              : const material.SizedBox(
                                  width: 0,
                                  height: double.infinity,
                                ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),

        // Calc Bar Footer
        if (_viewMode == ResultViewMode.grid)
          material.ValueListenableBuilder<GridCalcStats>(
            valueListenable: _selectionStats,
            builder: (_, stats, __) => DataGridCalcBar(stats: stats),
          ),
      ],
    ),
  );
  }
}

Future<void> _showSaveFileErrorDialog(material.BuildContext context) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => QueryaDialogCard(
      child: material.Padding(
        padding: const material.EdgeInsets.all(20),
        child: material.Column(
          mainAxisSize: material.MainAxisSize.min,
          crossAxisAlignment: material.CrossAxisAlignment.start,
          children: [
            const Text('Could not save file').semiBold().large(),
            const Gap(8),
            const Text('Check folder permissions or disk space.').muted().small(),
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

/// `14 ms`, `1.2 s`, `2 min 5 s`: what the elapsed badge shows.
String formatResultElapsed(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  if (d.inSeconds < 60) {
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  }
  return '${d.inMinutes} min ${d.inSeconds % 60} s';
}
