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

/// Opens a platform save dialog and streams [columns]/[rows] as CSV to disk.
Future<SaveResultGridCsvOutcome> saveResultGridCsvFile({
  required List<String> columns,
  required List<List<String>> rows,
  String? suggestedName,
}) async {
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
  IOSink? sink;
  try {
    sink = File(path).openWrite();
    await writeResultGridCsv(
      sink,
      columns: columns,
      rows: rows,
    );
    await sink.close();
    sink = null;
    return SaveResultGridCsvOutcome.written;
  } on Object {
    try {
      await sink?.close();
    } catch (_) {}
    return SaveResultGridCsvOutcome.error;
  }
}
