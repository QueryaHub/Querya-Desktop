/// RFC 4180–style CSV for a result grid (header + rows).
library;

import 'dart:io';
import 'dart:isolate';

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

/// Formats a single CSV data row, padding short rows to [columnCount].
String formatCsvDataRow(List<String> row, int columnCount) {
  final buf = StringBuffer();
  for (var i = 0; i < columnCount; i++) {
    if (i > 0) buf.write(',');
    if (i < row.length) buf.write(escapeCsvField(row[i]));
  }
  return buf.toString();
}

/// One line per row; pads short rows with empty cells to [columns.length].
///
/// Prefer [resultGridAsCsvAsync] for large grids on the UI isolate, and
/// [writeResultGridCsv] when writing to a file.
String resultGridAsCsv(List<String> columns, List<List<String>> rows) {
  final buf = StringBuffer();
  buf.write(columns.map(escapeCsvField).join(','));
  for (final row in rows) {
    buf.write('\n');
    buf.write(formatCsvDataRow(row, columns.length));
  }
  return buf.toString();
}

/// Builds CSV off the UI isolate so large grids do not freeze the main thread.
Future<String> resultGridAsCsvAsync(
  List<String> columns,
  List<List<String>> rows,
) {
  return Isolate.run(() => resultGridAsCsv(columns, rows));
}

/// Streams CSV to [sink] without assembling the full document in memory.
Future<void> writeResultGridCsv(
  IOSink sink, {
  required List<String> columns,
  required List<List<String>> rows,
}) async {
  sink.write(columns.map(escapeCsvField).join(','));
  var written = 0;
  for (final row in rows) {
    sink.write('\n');
    sink.write(formatCsvDataRow(row, columns.length));
    written++;
    // Yield periodically so a large export does not starve the event loop
    // when this runs on the UI isolate.
    if (written % 500 == 0) {
      await Future<void>.delayed(Duration.zero);
    }
  }
  await sink.flush();
}
