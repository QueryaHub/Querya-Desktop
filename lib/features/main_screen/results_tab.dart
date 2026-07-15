import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/widgets/virtual_selectable_text_view.dart';
import 'package:querya_desktop/features/main_screen/result_grid_view.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';
import 'package:querya_desktop/shared/widgets/widgets.dart';

/// Query output: grid, loading, error, or placeholder.
class ResultsTab extends StatelessWidget {
  const ResultsTab({
    super.key,
    this.columns = const [],
    this.rows = const [],
    this.errorMessage,
    this.isLoading = false,
    this.affectedRows,
    this.statusLine,
    this.showExportToolbar = true,
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? errorMessage;
  final bool isLoading;
  final int? affectedRows;
  final String? statusLine;
  final bool showExportToolbar;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const material.Center(
        child: material.CircularProgressIndicator(),
      );
    }
    if (errorMessage != null && errorMessage!.isNotEmpty) {
      return VirtualSelectableTextView(
        text: errorMessage!,
        style: material.TextStyle(
          fontFamily: 'monospace',
          fontSize: 12,
          color: Theme.of(context).colorScheme.destructive,
        ),
      );
    }
    if (columns.isEmpty && rows.isEmpty) {
      if (statusLine != null) {
        return material.Padding(
          padding: const material.EdgeInsets.all(16),
          child: Align(
            alignment: material.Alignment.topLeft,
            child: Text(statusLine!).muted().small(),
          ),
        );
      }
      if (affectedRows != null) {
        return material.Center(
          child: Text('Rows affected: $affectedRows').muted(),
        );
      }
      return material.Center(
        child: const Text('Run a query to see results here.').muted(),
      );
    }

    return material.Column(
      crossAxisAlignment: material.CrossAxisAlignment.stretch,
      children: [
        if (showExportToolbar && columns.isNotEmpty)
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
                  statusLine ??
                      (affectedRows != null
                          ? 'Rows affected: $affectedRows'
                          : '${rows.length} rows returned'),
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
                        columns: columns,
                        rows: rows,
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
                        columns: columns,
                        rows: rows,
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
          child: VirtualResultGrid(columns: columns, rows: rows),
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
