import 'dart:math' as math;

import 'package:shadcn_flutter/shadcn_flutter.dart';

/// Layout metrics for [VirtualResultGrid].
abstract final class ResultGridMetrics {
  static const double rowHeight = 36;
  static const double headerHeight = 36;
  static const double minColumnWidth = 56;
  static const double maxColumnWidth = 280;
  static const int columnWidthSampleRows = 40;
  static const int tooltipMinLength = 48;

  /// Extra columns built beyond the viewport to reduce scroll flicker.
  /// Columns built beyond each viewport edge. A wider margin means the window
  /// is rebuilt only every few columns of horizontal scroll, not on each one.
  static const int columnOverscan = 6;

  /// Hover tooltip: column SQL type when known, plus the cell value when long.
  static String? cellTooltipMessage({
    required String text,
    String? dataTypeName,
    String columnName = '',
  }) {
    final type = dataTypeName?.trim() ?? '';
    final typePart = type.isEmpty
        ? null
        : (columnName.isNotEmpty ? '$columnName · $type' : type);
    final showValue = text.length >= tooltipMinLength;
    if (typePart == null && !showValue) return null;
    if (typePart != null && showValue) return '$typePart\n$text';
    return typePart ?? text;
  }
}

/// Inclusive visible column window with spacer widths for off-screen columns.
@immutable
class ResultGridColumnWindow {
  const ResultGridColumnWindow({
    required this.first,
    required this.last,
    required this.leadingWidth,
    required this.trailingWidth,
  });

  /// Empty window (no columns).
  static const empty = ResultGridColumnWindow(
    first: 0,
    last: -1,
    leadingWidth: 0,
    trailingWidth: 0,
  );

  /// Inclusive first visible (or overscanned) column index.
  final int first;

  /// Inclusive last visible (or overscanned) column index.
  final int last;

  /// Width of columns strictly before [first] (left spacer).
  final double leadingWidth;

  /// Width of columns strictly after [last] (right spacer).
  final double trailingWidth;

  bool get isEmpty => last < first;

  int get columnCount => isEmpty ? 0 : last - first + 1;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResultGridColumnWindow &&
          first == other.first &&
          last == other.last &&
          leadingWidth == other.leadingWidth &&
          trailingWidth == other.trailingWidth;

  @override
  int get hashCode => Object.hash(first, last, leadingWidth, trailingWidth);
}

/// Computes fixed column widths from headers and a sample of [rows].
///
/// When provided, [outMaxRowChars] is populated with the maximum content
/// character length for each column across the sampled rows, which can be
/// passed to [distributeResultGridSpareWidth] to eliminate redundant row
/// sampling (#1349).
List<double> computeResultGridColumnWidths({
  required List<String> columns,
  required List<List<String>> rows,
  double minWidth = ResultGridMetrics.minColumnWidth,
  double maxWidth = ResultGridMetrics.maxColumnWidth,
  int sampleRowCount = ResultGridMetrics.columnWidthSampleRows,
  List<int>? outMaxRowChars,
}) {
  if (columns.isEmpty) return const [];

  final widths = List<double>.filled(columns.length, minWidth);
  final sample = rows.length < sampleRowCount ? rows.length : sampleRowCount;
  outMaxRowChars?.clear();

  for (var c = 0; c < columns.length; c++) {
    final headerWidth = columns[c].length * 7.5 + 38.0;
    var maxRowChars = 0;
    for (var r = 0; r < sample; r++) {
      if (c < rows[r].length && rows[r][c].length > maxRowChars) {
        maxRowChars = rows[r][c].length;
      }
    }
    outMaxRowChars?.add(maxRowChars);
    final contentWidth = maxRowChars * 7.5 + 24.0;
    final naturalWidth = math.max(headerWidth, contentWidth);
    widths[c] = naturalWidth.clamp(minWidth, maxWidth);
  }
  return widths;
}

/// Counts calls to `_GridCell._buildContextMenuItems` — should only fire when
/// a cell's context menu is actually opened (#983), not on every cell build.
int gridCellContextMenuItemsBuiltCount = 0;

/// Distributes spare viewport width adaptively to columns that benefit from expansion,
/// avoiding artificial stretching of compact columns.
///
/// If [maxRowChars] is provided (e.g. from [computeResultGridColumnWidths]),
/// it is reused directly to avoid redundant row sampling passes (#1349).
List<double> distributeResultGridSpareWidth({
  required List<double> columnWidths,
  required List<String> columns,
  required List<List<String>> rows,
  required double availableWidth,
  double maxColumnWidth = ResultGridMetrics.maxColumnWidth,
  int sampleRowCount = ResultGridMetrics.columnWidthSampleRows,
  List<int>? maxRowChars,
}) {
  if (columnWidths.isEmpty || columns.isEmpty) return columnWidths;

  final totalInitial = columnWidths.fold<double>(0.0, (sum, w) => sum + w);
  final spare = availableWidth - totalInitial;
  if (spare <= 0.5) return columnWidths;

  final sample = rows.length < sampleRowCount ? rows.length : sampleRowCount;
  final desiredWidths = List<double>.filled(columns.length, 0);
  final hasPrecomputedChars =
      maxRowChars != null && maxRowChars.length == columns.length;

  for (var c = 0; c < columns.length; c++) {
    final headerWidth = columns[c].length * 7.5 + 38.0;
    var rowChars = 0;
    if (hasPrecomputedChars) {
      rowChars = maxRowChars[c];
    } else {
      for (var r = 0; r < sample; r++) {
        if (c < rows[r].length && rows[r][c].length > rowChars) {
          rowChars = rows[r][c].length;
        }
      }
    }
    final contentWidth = rowChars * 7.5 + 24.0;
    desiredWidths[c] = math.max(headerWidth, contentWidth);
  }

  // Deficit columns: columns whose desired width exceeds the clamped initial width
  final deficits = List<double>.filled(columns.length, 0);
  var totalDeficit = 0.0;
  for (var c = 0; c < columns.length; c++) {
    if (desiredWidths[c] > columnWidths[c]) {
      final def = desiredWidths[c] - columnWidths[c];
      deficits[c] = def;
      totalDeficit += def;
    }
  }

  final result = List<double>.from(columnWidths);

  if (totalDeficit > 0) {
    if (spare <= totalDeficit) {
      final ratio = spare / totalDeficit;
      for (var c = 0; c < columns.length; c++) {
        if (deficits[c] > 0) {
          result[c] += deficits[c] * ratio;
        }
      }
      return result;
    } else {
      for (var c = 0; c < columns.length; c++) {
        if (deficits[c] > 0) {
          result[c] += deficits[c];
        }
      }
      final remainingSpare = spare - totalDeficit;
      _distributeRemainingSpare(result, remainingSpare);
      return result;
    }
  } else {
    _distributeRemainingSpare(result, spare);
    return result;
  }
}

void _distributeRemainingSpare(List<double> widths, double spare) {
  final weights = List<double>.filled(widths.length, 0);
  var totalWeight = 0.0;
  for (var i = 0; i < widths.length; i++) {
    if (widths[i] > 110) {
      final w = widths[i] - 100;
      weights[i] = w;
      totalWeight += w;
    }
  }

  if (totalWeight <= 0) {
    return;
  }

  final ratio = spare / totalWeight;
  for (var i = 0; i < widths.length; i++) {
    if (weights[i] > 0) {
      final extra = math.min(weights[i] * ratio, 120.0);
      widths[i] += extra;
    }
  }
}

/// Prefix sums: `offsets[i]` = sum of widths `[0, i)`.
List<double> computeResultGridColumnOffsets(List<double> columnWidths) {
  final offsets = List<double>.filled(columnWidths.length + 1, 0);
  for (var i = 0; i < columnWidths.length; i++) {
    offsets[i + 1] = offsets[i] + columnWidths[i];
  }
  return offsets;
}

/// Visible column range for a horizontal viewport (with overscan).
ResultGridColumnWindow computeVisibleColumnWindow({
  required List<double> columnWidths,
  required List<double> columnOffsets,
  required double scrollOffset,
  required double viewportWidth,
  int overscanColumns = ResultGridMetrics.columnOverscan,
}) {
  final n = columnWidths.length;
  if (n == 0) return ResultGridColumnWindow.empty;
  assert(columnOffsets.length == n + 1);

  final total = columnOffsets[n];
  if (viewportWidth <= 0) {
    return ResultGridColumnWindow(
      first: 0,
      last: n - 1,
      leadingWidth: 0,
      trailingWidth: 0,
    );
  }

  final start = scrollOffset.clamp(0.0, total);
  final end = (scrollOffset + viewportWidth).clamp(0.0, total);

  // First column with any pixel past [start]: smallest index where columnOffsets[first + 1] > start
  var first = 0;
  var low = 0;
  var high = n - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (columnOffsets[mid + 1] > start) {
      first = mid;
      high = mid - 1;
    } else {
      low = mid + 1;
    }
  }

  // Last column with any pixel before [end]: largest index where columnOffsets[last] < end
  var last = n - 1;
  low = 0;
  high = n - 1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (columnOffsets[mid] < end) {
      last = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }

  if (first > last) {
    first = last.clamp(0, n - 1);
  }

  first = (first - overscanColumns).clamp(0, n - 1);
  last = (last + overscanColumns).clamp(0, n - 1);

  return ResultGridColumnWindow(
    first: first,
    last: last,
    leadingWidth: columnOffsets[first],
    trailingWidth: total - columnOffsets[last + 1],
  );
}
