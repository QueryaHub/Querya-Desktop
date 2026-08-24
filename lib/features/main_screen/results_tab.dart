import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_toolbar.dart';
import 'package:querya_desktop/features/main_screen/result_grid_view.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Query output: grid, loading, error, or placeholder.
///
/// Render order in [_buildBody]: **loading** first (only when [isLoading]),
/// then **error** when [errorMessage] is non-empty (including when
/// `isLoading` is false), then status / affected / idle / grid content.
///
/// Mode changes (idle / loading / error / status / grid) morph via
/// [QueryaFadeSlide]. Keys are per **mode**, not per row — so grid data updates
/// and scroll rebuilds do not re-trigger the transition.
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

  @override
  material.State<ResultsTab> createState() => _ResultsTabState();
}

class _ResultsTabState extends material.State<ResultsTab> {
  int? _selectedRowIndex;

  @override
  Widget build(BuildContext context) {
    return QueryaFadeSlide(
      alignment: material.Alignment.center,
      offset: const material.Offset(0, 0.015),
      child: material.RepaintBoundary(child: _buildBody(context)),
    );
  }

  material.Widget _buildBody(material.BuildContext context) {
    if (widget.isLoading) {
      return const material.Center(
        key: material.ValueKey('results_mode_loading'),
        child: material.CircularProgressIndicator(),
      );
    }
    if (widget.errorMessage != null && widget.errorMessage!.isNotEmpty) {
      return material.KeyedSubtree(
        key: const material.ValueKey('results_mode_error'),
        child: VirtualSelectableTextView(
          text: widget.errorMessage!,
          style: material.TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Theme.of(context).colorScheme.destructive,
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

    return material.Column(
      key: const material.ValueKey('results_mode_grid'),
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        if (widget.stagingBuffer != null)
          DataGridStagingToolbar(
            stagingBuffer: widget.stagingBuffer!,
            selectedRowIndex: _selectedRowIndex,
            onApplyChanges: widget.onApplyChanges,
            isSaving: widget.isSaving,
          ),
        if (widget.showExportToolbar && widget.columns.isNotEmpty)
          material.Container(
            padding: const material.EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: material.BoxDecoration(
              color: Theme.of(context).colorScheme.card,
              border: material.Border(
                bottom: material.BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .border
                      .withValues(alpha: 0.5),
                ),
              ),
            ),
            child: material.Row(
              children: [
                material.Icon(
                  material.Icons.table_rows_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const Gap(6),
                Text(
                  widget.statusLine ??
                      (widget.affectedRows != null
                          ? 'Rows affected: ${widget.affectedRows}'
                          : '${effectiveRows.length} rows returned'),
                ).small().semiBold(),
                const material.Spacer(),
                ExportMenuButton(
                  label: 'Copy ▾',
                  icon: material.Icons.copy_rounded,
                  isSave: false,
                  onSelected: (format) {
                    unawaited(() async {
                      await DataExportService.copyToClipboard(
                        format,
                        columns: widget.columns,
                        rows: effectiveRows,
                      );
                    }());
                  },
                ),
                const Gap(6),
                ExportMenuButton(
                  label: 'Save ▾',
                  icon: material.Icons.save_alt_rounded,
                  isSave: true,
                  onSelected: (format) {
                    unawaited(() async {
                      final outcome = await DataExportService.saveToFile(
                        format,
                        columns: widget.columns,
                        rows: effectiveRows,
                      );
                      if (!context.mounted) return;
                      if (outcome == SaveExportOutcome.error) {
                        await _showSaveFileErrorDialog(context);
                      }
                    }());
                  },
                ),
              ],
            ),
          ),
        material.Expanded(
          child: VirtualResultGrid(
            columns: widget.columns,
            rows: widget.rows,
            stagingBuffer: widget.stagingBuffer,
            onRowSelected: (row) => setState(() => _selectedRowIndex = row),
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
        'Check folder permissions or disk space.',
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
