import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:querya_desktop/core/csv/result_grid_csv.dart';

enum DataExportFormat {
  csv,
  json,
  markdown,
  sqlDump,
}

enum SaveExportOutcome {
  cancelled,
  written,
  error,
}

/// Universal service for formatting, copying, and saving query result data.
class DataExportService {
  DataExportService._();

  /// Formats rows as CSV string using `resultGridAsCsv`.
  static String formatCsv(List<String> columns, List<List<String>> rows) {
    return resultGridAsCsv(columns, rows);
  }

  /// Formats rows as a JSON array of objects `[{"col": "val", ...}]`.
  static String formatJson(
    List<String> columns,
    List<List<String>> rows, {
    bool asObjectArray = true,
  }) {
    if (!asObjectArray) {
      final normalizedRows = rows
          .map(
            (r) => List<String>.generate(
              columns.length,
              (i) => i < r.length ? r[i] : '',
              growable: false,
            ),
          )
          .toList(growable: false);
      return const JsonEncoder.withIndent('  ').convert({
        'columns': columns,
        'rows': normalizedRows,
      });
    }

    final list = <Map<String, Object?>>[];
    for (final row in rows) {
      final obj = <String, Object?>{};
      for (var i = 0; i < columns.length; i++) {
        final colName = columns[i];
        final val = i < row.length ? row[i] : null;
        if (val == 'NULL' || val == null) {
          obj[colName] = null;
        } else {
          obj[colName] = val;
        }
      }
      list.add(obj);
    }
    return const JsonEncoder.withIndent('  ').convert(list);
  }

  /// Formats rows as a GitHub Flavored Markdown table.
  static String formatMarkdownTable(
    List<String> columns,
    List<List<String>> rows,
  ) {
    if (columns.isEmpty) return '';
    final buf = StringBuffer();

    String escapeMd(String s) {
      if (s == 'NULL') return '`NULL`';
      return s
          .replaceAll('|', '\\|')
          .replaceAll('\r\n', ' ')
          .replaceAll('\n', ' ');
    }

    buf.write('| ${columns.map(escapeMd).join(' | ')} |\n');
    buf.write('| ${columns.map((_) => '---').join(' | ')} |\n');

    for (final row in rows) {
      final padded = List<String>.generate(
        columns.length,
        (i) => i < row.length ? escapeMd(row[i]) : '`NULL`',
        growable: false,
      );
      buf.write('| ${padded.join(' | ')} |\n');
    }
    return buf.toString();
  }

  /// Formats rows as SQL INSERT statements (`INSERT INTO table (...) VALUES (...);`).
  static String formatSqlInsertDump(
    String tableName,
    List<String> columns,
    List<List<String>> rows,
  ) {
    if (columns.isEmpty || rows.isEmpty) return '';
    final safeTable =
        tableName.trim().isEmpty ? 'export_table' : tableName.trim();
    final colList = columns
        .map((c) => c.contains(' ') || c.contains('-') ? '"$c"' : c)
        .join(', ');

    final buf = StringBuffer();
    for (final row in rows) {
      buf.write('INSERT INTO $safeTable ($colList) VALUES (');
      for (var i = 0; i < columns.length; i++) {
        if (i > 0) buf.write(', ');
        if (i >= row.length || row[i] == 'NULL') {
          buf.write('NULL');
        } else {
          final val = row[i];
          final escaped = val.replaceAll("'", "''");
          buf.write("'$escaped'");
        }
      }
      buf.write(');\n');
    }
    return buf.toString();
  }

  /// Copies data in [format] to the system clipboard.
  static Future<void> copyToClipboard(
    DataExportFormat format, {
    required List<String> columns,
    required List<List<String>> rows,
    String tableName = 'export_table',
  }) async {
    final text = await formatAsync(
      format,
      columns: columns,
      rows: rows,
      tableName: tableName,
    );
    await Clipboard.setData(ClipboardData(text: text));
  }

  /// Formats data on a background isolate to prevent UI stutter on large datasets.
  static Future<String> formatAsync(
    DataExportFormat format, {
    required List<String> columns,
    required List<List<String>> rows,
    String tableName = 'export_table',
  }) {
    return Isolate.run(() {
      switch (format) {
        case DataExportFormat.csv:
          return formatCsv(columns, rows);
        case DataExportFormat.json:
          return formatJson(columns, rows);
        case DataExportFormat.markdown:
          return formatMarkdownTable(columns, rows);
        case DataExportFormat.sqlDump:
          return formatSqlInsertDump(tableName, columns, rows);
      }
    });
  }

  /// Opens a native file save dialog and writes the exported text to disk.
  static Future<SaveExportOutcome> saveToFile(
    DataExportFormat format, {
    required List<String> columns,
    required List<List<String>> rows,
    String tableName = 'export_table',
    String? suggestedName,
  }) async {
    final timestamp =
        DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    String ext;
    String label;
    switch (format) {
      case DataExportFormat.csv:
        ext = 'csv';
        label = 'CSV';
        break;
      case DataExportFormat.json:
        ext = 'json';
        label = 'JSON';
        break;
      case DataExportFormat.markdown:
        ext = 'md';
        label = 'Markdown';
        break;
      case DataExportFormat.sqlDump:
        ext = 'sql';
        label = 'SQL Script';
        break;
    }

    final name = suggestedName ?? '${tableName}_$timestamp.$ext';
    final location = await getSaveLocation(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: [ext]),
      ],
      suggestedName: name,
    );
    final path = location?.path;
    if (path == null || path.isEmpty) {
      return SaveExportOutcome.cancelled;
    }

    try {
      final content = await formatAsync(
        format,
        columns: columns,
        rows: rows,
        tableName: tableName,
      );
      await File(path).writeAsString(content);
      return SaveExportOutcome.written;
    } on Object {
      return SaveExportOutcome.error;
    }
  }
}
