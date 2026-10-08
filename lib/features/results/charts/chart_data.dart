/// Chart kinds offered by the Quick Charts tab.
enum QuickChartType { bar, line, pie }

/// One labelled point of a chart series.
class ChartPoint {
  const ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

/// Pure helpers that turn string grid rows into chart series.
class ChartData {
  ChartData._();

  /// Upper bound of plotted categories; the rest is folded into "Other".
  static const int maxPoints = 50;

  /// Parses a cell as a finite number; `null` for empty / non numeric cells.
  static double? parseNumber(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || value.isNaN || value.isInfinite) return null;
    return value;
  }

  /// Indices of columns whose non-empty cells are all numeric (at least one).
  static List<int> numericColumns(List<String> columns, List<List<String>> rows) {
    final result = <int>[];
    for (var c = 0; c < columns.length; c++) {
      var seen = 0;
      var ok = true;
      for (final row in rows) {
        if (c >= row.length) continue;
        final cell = row[c].trim();
        if (cell.isEmpty) continue;
        if (parseNumber(cell) == null) {
          ok = false;
          break;
        }
        seen++;
      }
      if (ok && seen > 0) result.add(c);
    }
    return result;
  }

  /// Builds a series using [labelColumn] as X (row index when `null`) and the
  /// numeric [valueColumn] as Y. Rows with a non numeric value are skipped.
  ///
  /// Pie charts aggregate equal labels, drop non-positive values and fold the
  /// tail beyond [maxPoints] into an "Other" slice.
  static List<ChartPoint> build({
    required List<List<String>> rows,
    required int? labelColumn,
    required int valueColumn,
    required QuickChartType type,
  }) {
    final points = <ChartPoint>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (valueColumn >= row.length) continue;
      final v = parseNumber(row[valueColumn]);
      if (v == null) continue;
      final label = labelColumn != null && labelColumn < row.length
          ? row[labelColumn]
          : '${i + 1}';
      points.add(ChartPoint(label, v));
    }

    if (type != QuickChartType.pie) {
      return points.length > maxPoints ? points.sublist(0, maxPoints) : points;
    }

    final sums = <String, double>{};
    for (final p in points) {
      if (p.value <= 0) continue;
      sums.update(p.label, (s) => s + p.value, ifAbsent: () => p.value);
    }
    final sorted = sums.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final head = sorted.take(maxPoints - 1).toList();
    final result = [for (final e in head) ChartPoint(e.key, e.value)];
    if (sorted.length > maxPoints - 1) {
      final rest = sorted
          .skip(maxPoints - 1)
          .fold<double>(0, (s, e) => s + e.value);
      result.add(ChartPoint('Other', rest));
    }
    return result;
  }
}
