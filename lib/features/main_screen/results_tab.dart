import 'dart:async' show unawaited;

import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/csv/result_grid_csv.dart';
import 'package:querya_desktop/core/csv/save_result_grid_csv.dart';
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
      return material.SingleChildScrollView(
        padding: const material.EdgeInsets.all(16),
        child: material.SelectableText(
          errorMessage!,
          style: material.TextStyle(
            fontFamily: 'monospace',
            fontSize: 12,
            color: Theme.of(context).colorScheme.destructive,
          ),
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
                      final outcome = await saveResultGridCsvFile(
                        columns: columns,
                        rows: rows,
                      );
                      if (!context.mounted) return;
                      if (outcome == SaveResultGridCsvOutcome.error) {
                        await _showSaveFileErrorDialog(context);
                      }
                    }());
                  },
                  leading: const material.Icon(
                    material.Icons.save_alt_rounded,
                    size: 14,
                  ),
                  child: const Text('Save as CSV…'),
                ),
                OutlineButton(
                  size: ButtonSize.small,
                  onPressed: () {
                    final csv = resultGridAsCsv(columns, rows);
                    Clipboard.setData(ClipboardData(text: csv));
                  },
                  leading: const material.Icon(
                    material.Icons.copy_rounded,
                    size: 14,
                  ),
                  child: const Text('Copy as CSV'),
                ),
              ],
            ),
          ),
        ),
        material.Expanded(
          child: material.Scrollbar(
            child: material.SingleChildScrollView(
              scrollDirection: material.Axis.horizontal,
              child: material.SingleChildScrollView(
                child: material.Table(
                  border: material.TableBorder.all(
                    color: Theme.of(context)
                        .colorScheme
                        .border
                        .withValues(alpha: 0.35),
                  ),
                  defaultColumnWidth: const material.IntrinsicColumnWidth(),
                  children: [
                    material.TableRow(
                      decoration: material.BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .muted
                            .withValues(alpha: 0.35),
                      ),
                      children: columns
                          .map(
                            (c) => material.Padding(
                              padding: const material.EdgeInsets.all(8),
                              child: Text(c).semiBold().small(),
                            ),
                          )
                          .toList(),
                    ),
                    ...rows.map(
                      (r) => material.TableRow(
                        children: r
                            .map(
                              (cell) => material.Padding(
                                padding: const material.EdgeInsets.all(8),
                                child: material.SelectableText(
                                  cell,
                                  style: const material.TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
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
