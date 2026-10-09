/// Chart kinds offered by the Quick Charts tab.
enum QuickChartType { bar, line, pie }

/// How rows that share an X label combine into one point.
enum ChartAggregation { none, sum, count, avg, min, max }

/// One labelled point of a chart series.
class ChartPoint {
  const ChartPoint(this.label, this.value);

  final String label;
  final double value;
}

/// Points ready to plot, plus how many parsed rows were left out of them.
class ChartSeries {
  const ChartSeries({required this.points, this.droppedRows = 0});

  final List<ChartPoint> points;

  /// Rows cut off by the line cap. Bar and pie fold their tail into "Other"
  /// instead, so they never report drops.
  final int droppedRows;
}

/// Pure helpers that turn string grid rows into chart series.
class ChartData {
  ChartData._();

  /// Line charts without aggregation plot at most this many points.
  static const int maxPoints = 50;

  /// Top N choices offered for bar and pie; `null` means every category.
  static const List<int?> topNChoices = [8, 10, 20, 50, null];

  /// Default for bar charts.
  static const int defaultTopN = 20;

  /// Default for pie: eight slices and "Other" stay readable in a legend.
  static const int pieTopN = 8;

  /// Name of the slice that collects the categories beyond Top N.
  static const String otherLabel = 'Other';

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

  /// Sum for an X column whose labels repeat across numeric rows, otherwise
  /// no aggregation. Row numbers never repeat, so they never aggregate.
  static ChartAggregation defaultAggregation({
    required List<List<String>> rows,
    required int? labelColumn,
    required int valueColumn,
  }) {
    if (labelColumn == null) return ChartAggregation.none;
    final seen = <String>{};
    for (final row in rows) {
      if (labelColumn >= row.length || valueColumn >= row.length) continue;
      if (parseNumber(row[valueColumn]) == null) continue;
      if (!seen.add(row[labelColumn])) return ChartAggregation.sum;
    }
    return ChartAggregation.none;
  }

  /// Builds a series using [labelColumn] as X (row index when `null`) and the
  /// numeric [valueColumn] as Y. Rows with a non numeric value are skipped.
  ///
  /// [aggregation] combines rows with equal labels first. Bar and pie then
  /// keep the top [topN] categories by value (`null` keeps all) and fold the
  /// rest into one "Other" point. Pie drops non-positive values. Line charts
  /// keep the first [maxPoints] points and report the rest in `droppedRows`.
  static ChartSeries build({
    required List<List<String>> rows,
    required int? labelColumn,
    required int valueColumn,
    required QuickChartType type,
    ChartAggregation aggregation = ChartAggregation.none,
    int? topN,
  }) {
    var points = _parse(rows, labelColumn, valueColumn);
    if (aggregation != ChartAggregation.none) {
      points = _aggregate(points, aggregation);
    }

    if (type == QuickChartType.line) {
      if (points.length <= maxPoints) return ChartSeries(points: points);
      return ChartSeries(
        points: points.sublist(0, maxPoints),
        droppedRows: points.length - maxPoints,
      );
    }

    if (type == QuickChartType.pie) {
      points = points.where((p) => p.value > 0).toList();
    }
    // Pie always reads largest first; bar keeps the row order unless Top N
    // ranks it.
    if (type == QuickChartType.pie) {
      points.sort((a, b) => b.value.compareTo(a.value));
    }
    if (topN == null || points.length <= topN) {
      return ChartSeries(points: points);
    }

    final ranked = [...points]..sort((a, b) => b.value.compareTo(a.value));
    final head = ranked.take(topN).toList();
    final rest = ranked.skip(topN).fold<double>(0, (s, p) => s + p.value);
    return ChartSeries(points: [...head, ChartPoint(otherLabel, rest)]);
  }

  static List<ChartPoint> _parse(
    List<List<String>> rows,
    int? labelColumn,
    int valueColumn,
  ) {
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
    return points;
  }

  /// Groups by label in first-seen order.
  static List<ChartPoint> _aggregate(
    List<ChartPoint> points,
    ChartAggregation aggregation,
  ) {
    final groups = <String, _Group>{};
    for (final p in points) {
      groups.putIfAbsent(p.label, _Group.new).add(p.value);
    }
    return [
      for (final e in groups.entries)
        ChartPoint(e.key, e.value.result(aggregation)),
    ];
  }
}

/// Running totals for one X label.
class _Group {
  double sum = 0;
  int count = 0;
  double min = double.infinity;
  double max = double.negativeInfinity;

  void add(double v) {
    sum += v;
    count++;
    if (v < min) min = v;
    if (v > max) max = v;
  }

  double result(ChartAggregation a) => switch (a) {
        ChartAggregation.none || ChartAggregation.sum => sum,
        ChartAggregation.count => count.toDouble(),
        ChartAggregation.avg => sum / count,
        ChartAggregation.min => min,
        ChartAggregation.max => max,
      };
}
