import 'dart:math' as math;
import 'package:flutter/foundation.dart';

/// Aggregated statistical results for a selection of grid cell values.
@immutable
class GridCalcStats {
  const GridCalcStats({
    required this.totalCount,
    required this.distinctCount,
    required this.numericCount,
    required this.nullCount,
    this.sum,
    this.average,
    this.median,
    this.min,
    this.max,
    this.stdDev,
  });

  static const empty = GridCalcStats(
    totalCount: 0,
    distinctCount: 0,
    numericCount: 0,
    nullCount: 0,
  );

  final int totalCount;
  final int distinctCount;
  final int numericCount;
  final int nullCount;
  final double? sum;
  final double? average;
  final double? median;
  final double? min;
  final double? max;
  final double? stdDev;

  bool get hasNumericStats => numericCount > 0 && sum != null;

  /// Formats all available statistics into a single copyable summary string.
  String toSummaryString() {
    final parts = <String>[
      'Count: $totalCount',
      'Distinct: $distinctCount',
    ];
    if (nullCount > 0) {
      parts.add('NULLs: $nullCount');
    }
    if (hasNumericStats) {
      parts.add('Sum: ${GridSelectionCalcEngine.formatNum(sum)}');
      parts.add('Avg: ${GridSelectionCalcEngine.formatNum(average)}');
      if (median != null) {
        parts.add('Median: ${GridSelectionCalcEngine.formatNum(median)}');
      }
      parts.add('Min: ${GridSelectionCalcEngine.formatNum(min)}');
      parts.add('Max: ${GridSelectionCalcEngine.formatNum(max)}');
      if (stdDev != null) {
        parts.add('StdDev: ${GridSelectionCalcEngine.formatNum(stdDev)}');
      }
    }
    return parts.join(' | ');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GridCalcStats &&
          totalCount == other.totalCount &&
          distinctCount == other.distinctCount &&
          numericCount == other.numericCount &&
          nullCount == other.nullCount &&
          sum == other.sum &&
          average == other.average &&
          median == other.median &&
          min == other.min &&
          max == other.max &&
          stdDev == other.stdDev;

  @override
  int get hashCode => Object.hash(
        totalCount,
        distinctCount,
        numericCount,
        nullCount,
        sum,
        average,
        median,
        min,
        max,
        stdDev,
      );
}

/// Calculation engine for computing stats (Count, Distinct, Sum, Avg, Median, Min, Max, StdDev) on grid selections.
abstract final class GridSelectionCalcEngine {
  /// Computes statistics for a list of string cell values.
  static GridCalcStats compute(List<String> values) {
    if (values.isEmpty) return GridCalcStats.empty;

    final total = values.length;
    var nulls = 0;
    final distinctSet = <String>{};
    final numericList = <double>[];
    var sum = 0.0;
    double? minVal;
    double? maxVal;

    for (final raw in values) {
      final trimmed = raw.trim();
      if (trimmed == 'NULL' || trimmed.isEmpty) {
        nulls++;
        continue;
      }

      distinctSet.add(trimmed);

      // Try parsing numeric values (stripping commas if present)
      final normalized = trimmed.replaceAll(',', '');
      final parsed = double.tryParse(normalized);
      if (parsed != null && !parsed.isNaN && !parsed.isInfinite) {
        numericList.add(parsed);
        sum += parsed;
        if (minVal == null || parsed < minVal) {
          minVal = parsed;
        }
        if (maxVal == null || parsed > maxVal) {
          maxVal = parsed;
        }
      }
    }

    final numericCount = numericList.length;
    final avg = numericCount > 0 ? sum / numericCount : null;

    // Calculate median
    double? median;
    if (numericCount > 0) {
      numericList.sort();
      final mid = numericCount ~/ 2;
      if (numericCount.isOdd) {
        median = numericList[mid];
      } else {
        median = (numericList[mid - 1] + numericList[mid]) / 2.0;
      }
    }

    // Calculate standard deviation
    double? stdDev;
    if (numericCount > 1 && avg != null) {
      var varianceSum = 0.0;
      for (final n in numericList) {
        varianceSum += math.pow(n - avg, 2);
      }
      stdDev = math.sqrt(varianceSum / (numericCount - 1));
    }

    return GridCalcStats(
      totalCount: total,
      distinctCount: distinctSet.length,
      numericCount: numericCount,
      nullCount: nulls,
      sum: numericCount > 0 ? sum : null,
      average: avg,
      median: median,
      min: minVal,
      max: maxVal,
      stdDev: stdDev,
    );
  }

  /// Formats a numeric stat cleanly for UI display.
  static String formatNum(double? val) {
    if (val == null) return '-';
    if (val == val.roundToDouble()) {
      return val.toInt().toString();
    }
    // Limit decimal precision to 4 decimal places
    final formatted = val.toStringAsFixed(4);
    return formatted.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }
}
