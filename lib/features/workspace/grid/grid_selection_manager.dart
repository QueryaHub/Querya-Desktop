import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart' hide TextExtension;

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
    // Cells go straight into the buffer: no per-row list and join (#1524).
    if (columns != null && columns.isNotEmpty) {
      for (var c = startColumn; c <= endColumn; c++) {
        if (c > startColumn) buffer.write('\t');
        buffer.write(_escapeTsv(c < columns.length ? columns[c] : ''));
      }
      buffer.writeln();
    }
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      for (var c = startColumn; c <= endColumn; c++) {
        if (c > startColumn) buffer.write('\t');
        buffer.write(_escapeTsv(c < rowData.length ? rowData[c] : ''));
      }
      buffer.writeln();
    }
    return buffer.toString().trimRight();
  }

  /// Formats selected cell values as a CSV string.
  /// If [columns] is provided, prepends a header row for the selected column range.
  String toCsv(List<List<String>> rows, {List<String>? columns}) {
    if (rows.isEmpty) return '';
    final buffer = StringBuffer();
    if (columns != null && columns.isNotEmpty) {
      for (var c = startColumn; c <= endColumn; c++) {
        if (c > startColumn) buffer.write(',');
        buffer.write(_escapeCsv(c < columns.length ? columns[c] : ''));
      }
      buffer.writeln();
    }
    for (var r = startRow; r <= endRow; r++) {
      if (r < 0 || r >= rows.length) continue;
      final rowData = rows[r];
      for (var c = startColumn; c <= endColumn; c++) {
        if (c > startColumn) buffer.write(',');
        buffer.write(_escapeCsv(c < rowData.length ? rowData[c] : ''));
      }
      buffer.writeln();
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
        } else if (_hasLeadingZeroDigits(val.trim())) {
          // Preserve numeric strings with leading zeros (e.g. '01234', '007')
          map[colName] = val;
        } else if ((_mayBeNumber(val) ? int.tryParse(val) : null)
            case final asInt?) {
          map[colName] = asInt;
        } else if ((_mayBeNumber(val) ? double.tryParse(val) : null)
            case final asDouble?) {
          map[colName] = asDouble;
        } else if (_equalsAsciiIgnoreCase(val, 'true')) {
          map[colName] = true;
        } else if (_equalsAsciiIgnoreCase(val, 'false')) {
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

  /// Cheap pre-check so text cells do not pay for two failed number parses:
  /// after any leading blanks (the parsers skip them) a number starts with a
  /// digit, a sign or a dot. A non-ASCII start is left to the parsers.
  static bool _mayBeNumber(String s) {
    for (var i = 0; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c == 0x20 || (c >= 0x09 && c <= 0x0D)) continue;
      return (c >= 0x30 && c <= 0x39) ||
          c == 0x2D ||
          c == 0x2B ||
          c == 0x2E ||
          c > 0x7F;
    }
    return false;
  }

  /// [lower] must be lower-case ASCII. Same answer as
  /// `s.toLowerCase() == lower`, without the copy.
  static bool _equalsAsciiIgnoreCase(String s, String lower) {
    if (s.length != lower.length) return false;
    for (var i = 0; i < s.length; i++) {
      var c = s.codeUnitAt(i);
      if (c >= 0x41 && c <= 0x5A) c += 0x20;
      if (c != lower.codeUnitAt(i)) return false;
    }
    return true;
  }

  /// `^0\d+$`: a zero followed by one or more ASCII digits and nothing else.
  static bool _hasLeadingZeroDigits(String s) {
    if (s.length < 2 || s.codeUnitAt(0) != 0x30) return false;
    for (var i = 1; i < s.length; i++) {
      final c = s.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }

  static String _escapeTsv(String val) => _quoteIfAny(val, 0x09);

  static String _escapeCsv(String val) => _quoteIfAny(val, 0x2C);

  /// Quotes [val] when it holds a quote, a line break or [separator]: one pass
  /// over the code units instead of one `contains` scan per character.
  static String _quoteIfAny(String val, int separator) {
    for (var i = 0; i < val.length; i++) {
      final c = val.codeUnitAt(i);
      if (c == 0x22 || c == 0x0A || c == 0x0D || c == separator) {
        return '"${val.replaceAll('"', '""')}"';
      }
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
