import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Coordinate of a cell in [VirtualResultGrid].
@immutable
class ResultGridCellCoordinate {
  const ResultGridCellCoordinate(this.row, this.column);

  final int row;
  final int column;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridCellCoordinate &&
          row == other.row &&
          column == other.column;

  @override
  int get hashCode => Object.hash(row, column);
}

/// Rectangular cell selection range in [VirtualResultGrid].
@immutable
class ResultGridSelection {
  const ResultGridSelection({
    required this.startRow,
    required this.startColumn,
    required this.endRow,
    required this.endColumn,
  });

  factory ResultGridSelection.fromPoints({
    required ResultGridCellCoordinate anchor,
    required ResultGridCellCoordinate focus,
  }) {
    final minR = anchor.row < focus.row ? anchor.row : focus.row;
    final maxR = anchor.row > focus.row ? anchor.row : focus.row;
    final minC = anchor.column < focus.column ? anchor.column : focus.column;
    final maxC = anchor.column > focus.column ? anchor.column : focus.column;
    return ResultGridSelection(
      startRow: minR,
      startColumn: minC,
      endRow: maxR,
      endColumn: maxC,
    );
  }

  final int startRow;
  final int startColumn;
  final int endRow;
  final int endColumn;

  bool contains(int row, int column) =>
      row >= startRow &&
      row <= endRow &&
      column >= startColumn &&
      column <= endColumn;

  int get rowCount => endRow - startRow + 1;
  int get columnCount => endColumn - startColumn + 1;

  /// Formats selected cell values as a Tab-Separated Values (TSV) string.
  /// If [columns] is provided, prepends a header row for the selected column range.
  String toTsv(List<List<String>> rows, {List<String>? columns}) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    if (columns != null && columns.isNotEmpty) {
      final headerCells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final col = c < columns.length ? columns[c] : '';
        headerCells.add(_escapeTsv(col));
      }
      buffer.writeln(headerCells.join('\t'));
    }
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final cells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final val = c < rowData.length ? rowData[c] : '';
        cells.add(_escapeTsv(val));
      }
      buffer.writeln(cells.join('\t'));
    }
    return buffer.toString().trimRight();
  }

  /// Formats selected cell values as a CSV string.
  /// If [columns] is provided, prepends a header row for the selected column range.
  String toCsv(List<List<String>> rows, {List<String>? columns}) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    if (columns != null && columns.isNotEmpty) {
      final headerCells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final col = c < columns.length ? columns[c] : '';
        headerCells.add(_escapeCsv(col));
      }
      buffer.writeln(headerCells.join(','));
    }
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final cells = <String>[];
      for (var c = startColumn; c <= endColumn; c++) {
        final val = c < rowData.length ? rowData[c] : '';
        cells.add(_escapeCsv(val));
      }
      buffer.writeln(cells.join(','));
    }
    return buffer.toString().trimRight();
  }

  /// Formats selected cell values as a formatted JSON string.
  /// Returns a JSON object for single-row selection, or a JSON array for multi-row selection.
  String toJson(List<String> columns, List<List<String>> rows) {
    if (rows.isEmpty || columns.isEmpty) return '[]';
    final result = <Map<String, dynamic>>[];
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      final map = <String, dynamic>{};
      for (var c = startColumn; c <= endColumn; c++) {
        final colName = c < columns.length ? columns[c] : 'col_$c';
        final val = c < rowData.length ? rowData[c] : '';
        if (val == 'NULL') {
          map[colName] = null;
        } else if (RegExp(r'^0\d+$').hasMatch(val.trim())) {
          // Preserve numeric strings with leading zeros (e.g. '01234', '007')
          map[colName] = val;
        } else if (int.tryParse(val) != null) {
          map[colName] = int.parse(val);
        } else if (double.tryParse(val) != null) {
          map[colName] = double.parse(val);
        } else if (val.toLowerCase() == 'true') {
          map[colName] = true;
        } else if (val.toLowerCase() == 'false') {
          map[colName] = false;
        } else {
          map[colName] = val;
        }
      }
      result.add(map);
    }
    if (result.length == 1) {
      return const JsonEncoder.withIndent('  ').convert(result.first);
    }
    return const JsonEncoder.withIndent('  ').convert(result);
  }

  static String _escapeTsv(String val) {
    if (val.contains('\t') ||
        val.contains('\n') ||
        val.contains('\r') ||
        val.contains('"')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }

  static String _escapeCsv(String val) {
    if (val.contains(',') ||
        val.contains('"') ||
        val.contains('\n') ||
        val.contains('\r')) {
      return '"${val.replaceAll('"', '""')}"';
    }
    return val;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridSelection &&
          startRow == other.startRow &&
          startColumn == other.startColumn &&
          endRow == other.endRow &&
          endColumn == other.endColumn;

  @override
  int get hashCode => Object.hash(startRow, startColumn, endRow, endColumn);
}
