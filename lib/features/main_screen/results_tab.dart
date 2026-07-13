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
  });

  final List<String> columns;
  final List<List<String>> rows;
  final String? errorMessage;
  final bool isLoading;
  final int? affectedRows;
  final String? statusLine;

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
        material.Padding(
          padding: const material.EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: material.Align(
            alignment: material.Alignment.centerRight,
            child: material.Wrap(
              alignment: material.WrapAlignment.end,
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () {
                    unawaited(() async {
                      await DataExportService.copyToClipboard(
                        DataExportFormat.csv,
                        columns: columns,
                        rows: rows,
                      );
                    }());
                  },
                  leading: const material.Icon(
                    material.Icons.copy_rounded,
                    size: 14,
                  ),
                  child: const Text('Copy as CSV'),
                ),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () {
                    unawaited(() async {
                      await DataExportService.copyToClipboard(
                        DataExportFormat.json,
                        columns: columns,
                        rows: rows,
                      );
                    }());
                  },
                  leading: const material.Icon(
                    material.Icons.copy_rounded,
                    size: 14,
                  ),
                  child: const Text('Copy as JSON'),
                ),
                _ExportMenuButton(
                  label: 'Copy formatted ▾',
                  icon: material.Icons.copy_all_rounded,
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
                _ExportMenuButton(
                  label: 'Save to file ▾',
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
        ),
        material.Expanded(
          child: VirtualResultGrid(columns: columns, rows: rows),
        ),
      ],
    );
  }
}

Future<void> _showSaveFileErrorDialog(material.BuildContext context) {
  return material.showDialog<void>(
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

class _ExportMenuButton extends StatelessWidget {
  const _ExportMenuButton({
    required this.label,
    required this.icon,
    required this.onSelected,
    required this.isSave,
  });

  final String label;
  final material.IconData icon;
  final material.ValueChanged<DataExportFormat> onSelected;
  final bool isSave;

  @override
  Widget build(BuildContext context) {
    return material.PopupMenuButton<DataExportFormat>(
      tooltip: label,
      onSelected: onSelected,
      itemBuilder: (context) => [
        material.PopupMenuItem(
          value: DataExportFormat.csv,
          child: material.Row(
            children: [
              const material.Icon(
                  material.Icons.table_chart_outlined, size: 16),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'CSV (.csv)' : 'Copy as CSV'),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.json,
          child: material.Row(
            children: [
              const material.Icon(
                  material.Icons.data_object_rounded, size: 16),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'JSON (.json)' : 'Copy as JSON'),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.markdown,
          child: material.Row(
            children: [
              const material.Icon(material.Icons.code_rounded, size: 16),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'Markdown Table (.md)' : 'Copy as Markdown Table'),
            ],
          ),
        ),
        material.PopupMenuItem(
          value: DataExportFormat.sqlDump,
          child: material.Row(
            children: [
              const material.Icon(material.Icons.storage_rounded, size: 16),
              const material.SizedBox(width: 8),
              material.Text(isSave ? 'SQL INSERT Dump (.sql)' : 'Copy as SQL Dump'),
            ],
          ),
        ),
      ],
      child: material.Container(
        padding: const material.EdgeInsets.symmetric(
            horizontal: 10, vertical: 6),
        decoration: material.BoxDecoration(
          border: material.Border.all(
            color: Theme.of(context).colorScheme.border,
          ),
          borderRadius: material.BorderRadius.circular(6),
        ),
        child: material.Row(
          mainAxisSize: material.MainAxisSize.min,
          children: [
            material.Icon(icon,
                size: 14, color: Theme.of(context).colorScheme.foreground),
            const material.SizedBox(width: 6),
            Text(label).small(),
          ],
        ),
      ),
    );
  }
}
