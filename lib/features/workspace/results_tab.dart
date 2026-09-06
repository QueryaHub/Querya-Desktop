import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
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
}

/// Query output: grid, loading, error, or placeholder.
class ResultsTab extends material.StatefulWidget {
  const ResultsTab({
    super.key,
    this.columns = const [],
    this.rows = const [],
    this.errorMessage,
    this.isLoading = false,
    this.affectedRows,
    this.statusLine,
    this.showExportToolbar = true,
    this.stagingBuffer,
    this.onApplyChanges,
    this.isSaving = false,
    this.errorAction,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? errorMessage;
  final bool isLoading;
  final int? affectedRows;
  final String? statusLine;
  final bool showExportToolbar;
  final DataGridStagingBuffer? stagingBuffer;
  final material.VoidCallback? onApplyChanges;
  final bool isSaving;
  final material.Widget? errorAction;

  @override
  material.State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends material.State<ResultsTab> {
  int? _selectedRowIndex;
  ResultViewMode _viewMode = ResultViewMode.grid;

  bool _showFilterBar = false;
  String _filterText = '';

  bool _showValuePanel = false;
  String? _focusedColumnName;
  String? _focusedCellValue;
  int? _focusedRowIndex;

  GridCalcStats _selectionStats = GridCalcStats.empty;

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
  void dispose() {
    _memoColumns = null;
    _memoEffectiveRows = null;
    _cachedFilteredRows = const [];
    _cachedFilteredIndices = null;
    super.dispose();
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (widget.isLoading) {
      return material.Center(
        key: const material.ValueKey('results_mode_loading'),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            const material.SizedBox(
              width: 16,
              height: 16,
              child: material.CircularProgressIndicator(strokeWidth: 2),
            ),
            const Gap(12),
            const Text('Executing query...').muted().small(),
          ],
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
                ? DataGridStagingToolbar(
                    stagingBuffer: widget.stagingBuffer!,
                    selectedRowIndex: _selectedRowIndex,
                    onApplyChanges: widget.onApplyChanges,
                    isSaving: widget.isSaving,
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
                    material.SizedBox(
                      height: 28,
                      child: material.SegmentedButton<ResultViewMode>(
                        segments: const [
                          material.ButtonSegment(
                            value: ResultViewMode.grid,
                            label: Text('Grid'),
                            icon: material.Icon(material.Icons.table_chart_outlined, size: 14),
                          ),
                          material.ButtonSegment(
                            value: ResultViewMode.groupings,
                            label: Text('Groupings'),
                            icon: material.Icon(material.Icons.grid_view_rounded, size: 14),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (selected) {
                          setState(() => _viewMode = selected.first);
                        },
                        showSelectedIcon: false,
                        style: material.SegmentedButton.styleFrom(
                          padding: const material.EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          visualDensity: material.VisualDensity.compact,
                        ),
                      ),
                    ),
                    const Gap(10),
                    Text(
                      widget.statusLine ??
                          (widget.affectedRows != null
                              ? 'Rows affected: ${widget.affectedRows}'
                              : '${filteredRows.length}${_filterText.isNotEmpty ? ' of ${effectiveRows.length}' : ''} rows'),
                    ).small().semiBold(),

                    const Gap(16),

                    // Toggle Quick Filter
                    material.IconButton(
                      icon: material.Icon(
                        _showFilterBar ? material.Icons.filter_alt : material.Icons.filter_alt_outlined,
                        size: 15,
                      ),
                      tooltip: 'Toggle Quick Filter',
                      padding: material.EdgeInsets.zero,
                      constraints: const material.BoxConstraints(minWidth: 28, minHeight: 28),
                      color: _showFilterBar || _filterText.isNotEmpty
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.mutedForeground,
                      onPressed: () {
                        setState(() => _showFilterBar = !_showFilterBar);
                      },
                    ),
                    const Gap(4),

                    // Toggle Value Side Panel
                    material.IconButton(
                      icon: material.Icon(
                        _showValuePanel ? material.Icons.dock : material.Icons.data_object_rounded,
                        size: 15,
                      ),
                      tooltip: 'Inspect Cell Panel',
                      padding: material.EdgeInsets.zero,
                      constraints: const material.BoxConstraints(minWidth: 28, minHeight: 28),
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
                      onSelected: (format) {
                        unawaited(() async {
                          await DataExportService.copyToClipboard(
                            format,
                            columns: widget.columns,
                            rows: filteredRows,
                          );
                          if (context.mounted) {
                            showAppToast(
                              context: context,
                              message: 'Copied ${filteredRows.length} rows as ${format.name.toUpperCase()}',
                              variant: AppToastVariant.success,
                            );
                          }
                        }());
                      },
                    ),
                    const Gap(6),
                    ExportMenuButton(
                      label: 'Save File ▾',
                      icon: material.Icons.download_rounded,
                      isSave: true,
                      onSelected: (format) {
                        unawaited(() async {
                          final outcome = await DataExportService.saveToFile(
                            format,
                            columns: widget.columns,
                            rows: filteredRows,
                          );
                          if (context.mounted) {
                            if (outcome == SaveExportOutcome.written) {
                              showAppToast(
                                context: context,
                                message: 'Exported ${filteredRows.length} rows',
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
            child: _viewMode == ResultViewMode.groupings
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
                          rowIndicesMapping: _cachedFilteredIndices,
                          onRowSelected: (row) => setState(() => _selectedRowIndex = row),
                          onSelectionValuesChanged: (values) {
                            if (values.isEmpty) {
                              setState(() => _selectionStats = GridCalcStats.empty);
                              return;
                            }
                            if (values.length < GridSelectionCalcEngine.computeThreshold) {
                              setState(() {
                                _selectionStats = GridSelectionCalcEngine.compute(values);
                              });
                            } else {
                              unawaited(
                                GridSelectionCalcEngine.computeAdaptive(values).then((stats) {
                                  if (mounted) {
                                    setState(() => _selectionStats = stats);
                                  }
                                }),
                              );
                            }
                          },
                          onCellFocused: (colName, cellVal, rowIdx) {
                            setState(() {
                              _focusedColumnName = colName;
                              _focusedCellValue = cellVal;
                              _focusedRowIndex = rowIdx;
                            });
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
                      material.AnimatedSize(
                        duration: context.motionDuration(QueryaMotion.standard),
                        curve: context.motionCurve(QueryaMotion.enter),
                        alignment: material.Alignment.centerRight,
                        child: (_showValuePanel &&
                                _focusedColumnName != null &&
                                _focusedCellValue != null)
                            ? DataGridValuePanel(
                                columnName: _focusedColumnName!,
                                cellValue: _focusedCellValue!,
                                rowIndex: _focusedRowIndex,
                                onClose: () => setState(() => _showValuePanel = false),
                                onUpdateValue: widget.stagingBuffer != null &&
                                        _focusedRowIndex != null &&
                                        _focusedColumnName != null
                                    ? (newVal) {
                                        final colIdx = widget.columns.indexOf(_focusedColumnName!);
                                        if (colIdx != -1) {
                                          widget.stagingBuffer!.setCell(
                                            _focusedRowIndex!,
                                            colIdx,
                                            newVal,
                                          );
                                        }
                                      }
                                    : null,
                              )
                            : const material.SizedBox(width: 0, height: double.infinity),
                      ),
                    ],
                  ),
          ),
        ),

        // Calc Bar Footer
        if (_viewMode == ResultViewMode.grid)
          DataGridCalcBar(stats: _selectionStats),
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
