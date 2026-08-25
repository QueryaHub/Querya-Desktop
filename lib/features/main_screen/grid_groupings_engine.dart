import 'package:flutter/foundation.dart';

/// Aggregation operation to perform on groups.
enum GroupingAggType {
  count('COUNT'),
  sum('SUM'),
  avg('AVG'),
  min('MIN'),
  max('MAX');

  const GroupingAggType(this.label);
  final String label;
}

/// Sort criteria for grouping categories.
enum GroupSortBy {
  count('Count'),
  key('Group Key'),
  aggregate('Aggregate');

  const GroupSortBy(this.label);
  final String label;
}

/// Configuration for group aggregations.
@immutable
class GroupAggregationConfig {
  const GroupAggregationConfig({
    this.aggType = GroupingAggType.count,
    this.targetColIndex,
  });

  final GroupingAggType aggType;
  final int? targetColIndex;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupAggregationConfig &&
          aggType == other.aggType &&
          targetColIndex == other.targetColIndex;

  @override
  int get hashCode => Object.hash(aggType, targetColIndex);
}

/// Represents an aggregated group in Groupings / Pivot View (supports nested sub-groups).
@immutable
class GroupedCategory {
  const GroupedCategory({
    required this.groupKey,
    required this.count,
    required this.percentage,
    required this.rows,
    this.aggValue,
    this.subGroups = const [],
    this.level = 0,
  });

  final String groupKey;
  final int count;
  final double percentage;
  final List<List<String>> rows;
  final double? aggValue;
  final List<GroupedCategory> subGroups;
  final int level;

  bool get hasSubGroups => subGroups.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupedCategory &&
          groupKey == other.groupKey &&
          count == other.count &&
          percentage == other.percentage &&
          aggValue == other.aggValue &&
          level == other.level;

  @override
  int get hashCode => Object.hash(groupKey, count, percentage, aggValue, level);
}

/// Engine to construct multi-column pivot / hierarchical grouping breakdown tables.
abstract final class GridGroupingsEngine {
  /// Builds multi-level groups by [groupColIndices] with optional aggregation and sorting.
  static List<GroupedCategory> buildGroups({
    required List<int> groupColIndices,
    required List<List<String>> rows,
    GroupAggregationConfig aggConfig = const GroupAggregationConfig(),
    GroupSortBy sortBy = GroupSortBy.count,
    bool sortAscending = false,
  }) {
    if (rows.isEmpty || groupColIndices.isEmpty) return const [];

    return _buildSubGroups(
      groupColIndices: groupColIndices,
      levelIndex: 0,
      rows: rows,
      totalRootRows: rows.length,
      aggConfig: aggConfig,
      sortBy: sortBy,
      sortAscending: sortAscending,
    );
  }

  static List<GroupedCategory> _buildSubGroups({
    required List<int> groupColIndices,
    required int levelIndex,
    required List<List<String>> rows,
    required int totalRootRows,
    required GroupAggregationConfig aggConfig,
    required GroupSortBy sortBy,
    required bool sortAscending,
  }) {
    if (levelIndex >= groupColIndices.length || rows.isEmpty) return const [];

    final colIndex = groupColIndices[levelIndex];
    final map = <String, List<List<String>>>{};

    for (final row in rows) {
      final key = colIndex < row.length ? row[colIndex] : 'NULL';
      final effectiveKey = key.isEmpty ? '(Empty)' : key;
      map.putIfAbsent(effectiveKey, () => []).add(row);
    }

    final categories = <GroupedCategory>[];
    final hasNextLevel = levelIndex + 1 < groupColIndices.length;

    map.forEach((key, categoryRows) {
      final count = categoryRows.length;
      final pct = totalRootRows > 0 ? (count / totalRootRows) * 100 : 0.0;
      final agg = _computeAggregation(categoryRows, aggConfig);

      List<GroupedCategory> subGroups = const [];
      if (hasNextLevel) {
        subGroups = _buildSubGroups(
          groupColIndices: groupColIndices,
          levelIndex: levelIndex + 1,
          rows: categoryRows,
          totalRootRows: totalRootRows,
          aggConfig: aggConfig,
          sortBy: sortBy,
          sortAscending: sortAscending,
        );
      }

      categories.add(
        GroupedCategory(
          groupKey: key,
          count: count,
          percentage: pct,
          rows: categoryRows,
          aggValue: agg,
          subGroups: subGroups,
          level: levelIndex,
        ),
      );
    });

    // Sorting
    categories.sort((a, b) {
      int cmp;
      switch (sortBy) {
        case GroupSortBy.count:
          cmp = a.count.compareTo(b.count);
          break;
        case GroupSortBy.key:
          cmp = a.groupKey.compareTo(b.groupKey);
          break;
        case GroupSortBy.aggregate:
          final aVal = a.aggValue ?? (a.count.toDouble());
          final bVal = b.aggValue ?? (b.count.toDouble());
          cmp = aVal.compareTo(bVal);
          break;
      }
      return sortAscending ? cmp : -cmp;
    });

    return categories;
  }

  static double? _computeAggregation(
    List<List<String>> rows,
    GroupAggregationConfig config,
  ) {
    if (config.aggType == GroupingAggType.count) {
      return rows.length.toDouble();
    }
    if (config.targetColIndex == null) return null;

    final targetCol = config.targetColIndex!;
    final numbers = <double>[];

    for (final row in rows) {
      if (targetCol < row.length) {
        final val = row[targetCol].replaceAll(',', '').trim();
        final parsed = double.tryParse(val);
        if (parsed != null && !parsed.isNaN && !parsed.isInfinite) {
          numbers.add(parsed);
        }
      }
    }

    if (numbers.isEmpty) return null;

    switch (config.aggType) {
      case GroupingAggType.count:
        return numbers.length.toDouble();
      case GroupingAggType.sum:
        return numbers.reduce((a, b) => a + b);
      case GroupingAggType.avg:
        return numbers.reduce((a, b) => a + b) / numbers.length;
      case GroupingAggType.min:
        return numbers.reduce((a, b) => a < b ? a : b);
      case GroupingAggType.max:
        return numbers.reduce((a, b) => a > b ? a : b);
    }
  }

  /// Exports pivot summary to CSV format.
  static String exportPivotToCsv({
    required List<GroupedCategory> groups,
    required String groupByColumnName,
    GroupAggregationConfig aggConfig = const GroupAggregationConfig(),
  }) {
    final buffer = StringBuffer();
    buffer.writeln('Group Key,Count,Percentage,Aggregate');

    for (final g in groups) {
      final aggStr = g.aggValue != null ? g.aggValue!.toStringAsFixed(2) : '-';
      buffer.writeln(
        '"${g.groupKey.replaceAll('"', '""')}",${g.count},${g.percentage.toStringAsFixed(2)}%,$aggStr',
      );
    }

    return buffer.toString();
  }
}
