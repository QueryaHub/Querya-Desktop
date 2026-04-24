import 'dart:convert';

/// JSON object: `{ "columns": [...], "rows": [[...], ...] }`.
///
/// Short rows are padded with empty strings to [columns.length] (same as CSV).
String resultGridAsJson(List<String> columns, List<List<String>> rows) {
  final normalizedRows = rows
      .map(
        (r) => List<String>.generate(
          columns.length,
          (i) => i < r.length ? r[i] : '',
          growable: false,
        ),
      )
      .toList(growable: false);
  return jsonEncode(<String, Object?>{
    'columns': columns,
    'rows': normalizedRows,
  });
}
