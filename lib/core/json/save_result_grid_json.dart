import 'dart:io';

import 'package:file_selector/file_selector.dart';

import 'package:querya_desktop/core/json/result_grid_json.dart';

/// Outcome of [saveResultGridJsonFile].
enum SaveResultGridJsonOutcome {
  cancelled,
  written,
  error,
}

/// Opens a platform save dialog and writes [columns]/[rows] as JSON.
Future<SaveResultGridJsonOutcome> saveResultGridJsonFile({
  required List<String> columns,
  required List<List<String>> rows,
  String? suggestedName,
}) async {
  final json = resultGridAsJson(columns, rows);
  final name = suggestedName ??
      'querya_results_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';
  final location = await getSaveLocation(
    acceptedTypeGroups: const [
      XTypeGroup(label: 'JSON', extensions: ['json']),
    ],
    suggestedName: name,
  );
  final path = location?.path;
  if (path == null || path.isEmpty) {
    return SaveResultGridJsonOutcome.cancelled;
  }
  try {
    await File(path).writeAsString(json);
    return SaveResultGridJsonOutcome.written;
  } on Object {
    return SaveResultGridJsonOutcome.error;
  }
}
