import 'dart:async';

import 'package:flutter/foundation.dart' as foundation;

/// Sorting direction for [VirtualResultGrid].
enum ResultGridSortOrder {
  ascending,
  descending,
}

enum _SortKeyType { nullOrEmpty, numeric, dateTime, string }

class _SortKey implements Comparable<_SortKey> {
  final _SortKeyType type;
  final num? numVal;
  final DateTime? dtVal;
  final String strLower;
  final String strRaw;

  _SortKey._({
    required this.type,
    this.numVal,
    this.dtVal,
    this.strLower = '',
    this.strRaw = '',
  });

  factory _SortKey.parse(String val) {
    if (val == 'NULL' || val.isEmpty) {
      return _SortKey._(type: _SortKeyType.nullOrEmpty);
    }
    final n = num.tryParse(val);
    if (n != null) {
      return _SortKey._(type: _SortKeyType.numeric, numVal: n, strRaw: val);
    }
    final dt = DateTime.tryParse(val);
    if (dt != null) {
      return _SortKey._(type: _SortKeyType.dateTime, dtVal: dt, strRaw: val);
    }
    return _SortKey._(
      type: _SortKeyType.string,
      strLower: val.toLowerCase(),
      strRaw: val,
    );
  }

  @override
  int compareTo(_SortKey other) {
    if (type == _SortKeyType.nullOrEmpty &&
        other.type == _SortKeyType.nullOrEmpty) {
      return 0;
    }
    if (type == _SortKeyType.nullOrEmpty) return 1;
    if (other.type == _SortKeyType.nullOrEmpty) return -1;

    if (type == _SortKeyType.numeric && other.type == _SortKeyType.numeric) {
      return numVal!.compareTo(other.numVal!);
    }
    if (type == _SortKeyType.dateTime && other.type == _SortKeyType.dateTime) {
      return dtVal!.compareTo(other.dtVal!);
    }

    final aLower =
        type == _SortKeyType.string ? strLower : strRaw.toLowerCase();
    final bLower = other.type == _SortKeyType.string
        ? other.strLower
        : other.strRaw.toLowerCase();
    final cmp = aLower.compareTo(bLower);
    if (cmp != 0) return cmp;

    return strRaw.compareTo(other.strRaw);
  }
}

/// Result of sorting rows in [VirtualResultGrid], preserving model indices.
class SortedResultGridData {
  final List<List<String>> rows;
  final List<int> sortedToModelIndices;

  const SortedResultGridData({
    required this.rows,
    required this.sortedToModelIndices,
  });
}

/// Sorts rows by the specified column index with natural numeric / temporal / lexicographic comparison.
/// Uses Schwartzian transform (Decorate-Sort-Undecorate) to precompute sort keys in O(N) time.
/// Returns [SortedResultGridData] containing sorted rows and their corresponding model indices.
SortedResultGridData sortResultGridRowsWithIndices({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
}) {
  if (rows.isEmpty || columnIndex < 0) {
    return SortedResultGridData(
      rows: rows,
      sortedToModelIndices:
          List<int>.generate(rows.length, (i) => i, growable: false),
    );
  }
  final n = rows.length;

  final keys = List<_SortKey>.generate(n, (i) {
    final row = rows[i];
    final val = columnIndex < row.length ? row[columnIndex] : '';
    return _SortKey.parse(val);
  }, growable: false);

  final indices = List<int>.generate(n, (i) => i, growable: false);

  indices.sort((a, b) {
    final cmp = keys[a].compareTo(keys[b]);
    return order == ResultGridSortOrder.ascending ? cmp : -cmp;
  });

  final sortedRows =
      List<List<String>>.generate(n, (i) => rows[indices[i]], growable: false);
  return SortedResultGridData(
    rows: sortedRows,
    sortedToModelIndices: indices,
  );
}

/// Sorts rows by the specified column index with natural numeric / temporal / lexicographic comparison.
List<List<String>> sortResultGridRows({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
}) {
  return sortResultGridRowsWithIndices(
    rows: rows,
    columnIndex: columnIndex,
    order: order,
  ).rows;
}

/// Default threshold for offloading data grid sorting to a background isolate.
const int kSortIsolateThreshold = 3000;

class SortIsolateParams {
  final List<List<String>> rows;
  final int columnIndex;
  final ResultGridSortOrder order;

  const SortIsolateParams({
    required this.rows,
    required this.columnIndex,
    required this.order,
  });
}

SortedResultGridData sortResultGridRowsWithIndicesIsolate(
    SortIsolateParams params) {
  return sortResultGridRowsWithIndices(
    rows: params.rows,
    columnIndex: params.columnIndex,
    order: params.order,
  );
}

/// Adaptive sort function that executes synchronously for small lists (< [kSortIsolateThreshold]),
/// and offloads to a background isolate for large datasets to keep UI fluid.
Future<SortedResultGridData> sortResultGridRowsWithIndicesAdaptive({
  required List<List<String>> rows,
  required int columnIndex,
  required ResultGridSortOrder order,
  int threshold = kSortIsolateThreshold,
}) async {
  if (rows.length < threshold) {
    return sortResultGridRowsWithIndices(
      rows: rows,
      columnIndex: columnIndex,
      order: order,
    );
  }
  return foundation.compute(
    sortResultGridRowsWithIndicesIsolate,
    SortIsolateParams(rows: rows, columnIndex: columnIndex, order: order),
  );
}
