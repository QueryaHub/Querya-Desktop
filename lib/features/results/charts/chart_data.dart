/// Chart kinds offered by the Quick Charts tab.
enum QuickChartType { bar, line, pie }

/// How rows that share an X label combine into one point.
enum ChartAggregation { none, sum, count, avg, min, max }

/// One labelled point of a chart series.
class ChartPoint {
  const ChartPoint(this.label, this.value, {this.time});

  final String label;
  final double value;

  /// The label as a date or timestamp, when the X column holds dates.
  final DateTime? time;
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

  static final _isoTime = RegExp(
    r'^\d{4}-\d{2}-\d{2}([T ]\d{2}:\d{2}(:\d{2}(\.\d+)?)?)?(Z|[+-]\d{2}:?\d{2})?$',
  );
  static final _hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$');

  /// Parses an ISO date (`2026-01-31`) or timestamp (`2026-01-31 10:00`,
  /// `2026-01-31T10:00:00Z`). Without a zone the wall-clock fields are kept, so
  /// a day stays a day whatever the machine's time zone is.
  static DateTime? parseTime(String raw) {
    final text = raw.trim();
    if (!_isoTime.hasMatch(text)) return null;
    final parsed = DateTime.tryParse(text.replaceFirst(' ', 'T'));
    if (parsed == null) return null;
    // DateTime rolls an impossible date over (2026-13-45 becomes 2027-02-14);
    // the fields must read back as typed.
    if (parsed.year != int.parse(text.substring(0, 4)) ||
        parsed.month != int.parse(text.substring(5, 7)) ||
        parsed.day != int.parse(text.substring(8, 10))) {
      return null;
    }
    if (text.length >= 16 &&
        (parsed.hour != int.parse(text.substring(11, 13)) ||
            parsed.minute != int.parse(text.substring(14, 16)))) {
      return null;
    }
    if (_hasZone.hasMatch(text)) return parsed.toUtc();
    return DateTime.utc(parsed.year, parsed.month, parsed.day, parsed.hour,
        parsed.minute, parsed.second, parsed.millisecond, parsed.microsecond);
  }

  /// Whether every non-empty cell of [column] is a date or timestamp.
  static bool isTimeColumn(List<List<String>> rows, int column) {
    var seen = 0;
    for (final row in rows) {
      if (column >= row.length) continue;
      final cell = row[column].trim();
      if (cell.isEmpty) continue;
      if (parseTime(cell) == null) return false;
      seen++;
    }
    return seen > 0;
  }

  /// Earliest time among [points]; null unless every point has a time.
  static DateTime? timeOrigin(List<ChartPoint> points) {
    if (points.isEmpty || points.any((p) => p.time == null)) return null;
    return points.map((p) => p.time!).reduce((a, b) => a.isBefore(b) ? a : b);
  }

  /// Days from the earliest point for every point, so the X axis places them
  /// at their real distance. Null unless every point has a time.
  static List<double>? timeOffsets(List<ChartPoint> points) {
    final origin = timeOrigin(points);
    if (origin == null) return null;
    return [
      for (final p in points)
        p.time!.difference(origin).inMicroseconds / Duration.microsecondsPerDay,
    ];
  }

  /// Length of the time axis: from the earliest point to the latest.
  static Duration timeSpan(List<ChartPoint> points) {
    final origin = timeOrigin(points);
    if (origin == null) return Duration.zero;
    final last = points.map((p) => p.time!).reduce((a, b) => a.isAfter(b) ? a : b);
    return last.difference(origin);
  }

  /// Tick label for [time] on an axis spanning [span]: hours for a span under
  /// two days, days under about 13 months, months beyond.
  static String timeTickLabel(DateTime time, Duration span) {
    String two(int v) => v.toString().padLeft(2, '0');
    if (span < const Duration(days: 2)) {
      return '${two(time.hour)}:${two(time.minute)}';
    }
    if (span < const Duration(days: 400)) {
      return '${time.year}-${two(time.month)}-${two(time.day)}';
    }
    return '${time.year}-${two(time.month)}';
  }

  /// Index of the point whose X offset is nearest to [x].
  static int nearestOffset(List<double> offsets, double x) {
    var best = 0;
    for (var i = 1; i < offsets.length; i++) {
      if ((offsets[i] - x).abs() < (offsets[best] - x).abs()) best = i;
    }
    return best;
  }

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
      // Dates on the X axis plot in time order, at their real distance.
      if (labelColumn != null &&
          isTimeColumn(rows, labelColumn) &&
          points.every((p) => p.time != null)) {
        points = [...points]..sort((a, b) => a.time!.compareTo(b.time!));
      }
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

  /// Largest-triangle-three-buckets: reduces [points] to [target] points that
  /// keep the shape of the series, so peaks survive. The first and last points
  /// are always kept; shorter series come back unchanged.
  static List<ChartPoint> downsample(List<ChartPoint> points, int target) {
    final n = points.length;
    if (target < 3 || n <= target) return points;
    final out = <ChartPoint>[points.first];
    final every = (n - 2) / (target - 2);
    var a = 0;
    for (var i = 0; i < target - 2; i++) {
      // Average of the next bucket: the third corner of each triangle.
      final nextStart = ((i + 1) * every).floor() + 1;
      final nextEnd = (((i + 2) * every).floor() + 1).clamp(0, n).toInt();
      var avgX = 0.0, avgY = 0.0;
      for (var k = nextStart; k < nextEnd; k++) {
        avgX += k;
        avgY += points[k].value;
      }
      final count = nextEnd - nextStart;
      avgX /= count;
      avgY /= count;

      final rangeStart = (i * every).floor() + 1;
      final rangeEnd = (((i + 1) * every).floor() + 1).clamp(0, n).toInt();
      final ax = a.toDouble(), ay = points[a].value;
      var best = -1.0, pick = rangeStart;
      for (var k = rangeStart; k < rangeEnd; k++) {
        final area = ((ax - avgX) * (points[k].value - ay) -
                (ax - k) * (avgY - ay))
            .abs();
        if (area > best) {
          best = area;
          pick = k;
        }
      }
      out.add(points[pick]);
      a = pick;
    }
    out.add(points.last);
    return out;
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
      points.add(ChartPoint(label, v, time: parseTime(label)));
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
      groups.putIfAbsent(p.label, () => _Group()..time = p.time).add(p.value);
    }
    return [
      for (final e in groups.entries)
        ChartPoint(e.key, e.value.result(aggregation), time: e.value.time),
    ];
  }
}

/// Running totals for one X label.
class _Group {
  DateTime? time;
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
