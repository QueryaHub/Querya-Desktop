/// RFC 4180–style CSV for a result grid (header + rows).
library;

String escapeCsvField(String s) {
  final needsQuotes = s.contains(',') ||
      s.contains('"') ||
      s.contains('\n') ||
      s.contains('\r');
  if (needsQuotes) {
    return '"${s.replaceAll('"', '""')}"';
  }
  return s;
}

/// One line per row; pads short rows with empty cells to [columns.length].
String resultGridAsCsv(List<String> columns, List<List<String>> rows) {
  final lines = <String>[
    columns.map(escapeCsvField).join(','),
    ...rows.map((r) {
      final cells = List<String>.generate(
        columns.length,
        (i) => i < r.length ? escapeCsvField(r[i]) : '',
        growable: false,
      );
      return cells.join(',');
    }),
  ];
  return lines.join('\n');
}
