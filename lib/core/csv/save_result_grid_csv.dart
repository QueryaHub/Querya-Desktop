import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'package:querya_desktop/core/csv/result_grid_csv.dart';

/// Outcome of [saveResultGridCsvFile].
enum SaveResultGridCsvOutcome {
  /// User cancelled the save dialog or no path was returned.
  cancelled,

  /// Bytes were written successfully.
  written,

  /// A path was chosen but writing failed.
  error,
}

/// Opens a platform save dialog and writes [columns]/[rows] as CSV.
Future<SaveResultGridCsvOutcome> saveResultGridCsvFile({
  required List<String> columns,
  required List<List<String>> rows,
  String? suggestedName,
}) async {
  final csv = resultGridAsCsv(columns, rows);
  final name = suggestedName ??
      'querya_results_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'CSV', extensions: ['csv']),
    ],
    suggestedName: name,
  );
  final path = location?.path;
  if (path == null || path.isEmpty) {
    return SaveResultGridCsvOutcome.cancelled;
  }
  try {
    await File(path).writeAsString(csv);
    return SaveResultGridCsvOutcome.written;
  } on Object {
    return SaveResultGridCsvOutcome.error;
  }
}
