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

  /// The instant of a date / timestamp, in microseconds since the epoch.
  final int dtMicros;
  final String strLower;
  final String strRaw;

  _SortKey._({
    required this.type,
    this.numVal,
    this.dtMicros = 0,
    this.strLower = '',
    this.strRaw = '',
  });

  factory _SortKey.parse(String val, Map<int, int> localOffsets) {
    if (val == 'NULL' || val.isEmpty) {
      return _SortKey._(type: _SortKeyType.nullOrEmpty);
    }
    final n = num.tryParse(val);
    if (n != null) {
      return _SortKey._(type: _SortKeyType.numeric, numVal: n, strRaw: val);
    }
    final micros = isoMicrosSinceEpoch(val, localOffsets: localOffsets) ??
        DateTime.tryParse(val)?.microsecondsSinceEpoch;
    if (micros != null) {
      return _SortKey._(
        type: _SortKeyType.dateTime,
        dtMicros: micros,
        strRaw: val,
      );
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
      return dtMicros.compareTo(other.dtMicros);
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

/// [s] as `DateTime.parse(s).microsecondsSinceEpoch` for the shapes database
/// drivers print, read from the code units: `YYYY-MM-DD`, then optionally
/// `[T ]HH:MM`, `:SS`, `.fraction` and `Z` / `±HH[[:]MM]`. Null for any other
/// shape, which the caller hands to [DateTime.tryParse]: this is only a
/// shortcut past its regex, with the same result (#1533).
///
/// Without a zone the time is local, as in [DateTime.parse]; fields out of
/// range roll over the same way, because they go through the same
/// constructors. The fraction keeps its first six digits, as there.
///
/// The local constructor asks the system for the zone offset on every call
/// (~4 µs, nearly all of a timestamp sort). With [localOffsets], one map per
/// sort, a day whose offset is the same at its start and its end is looked
/// up once and the time is computed from the UTC fields; a day with a
/// daylight-saving change still goes through the local constructor.
@foundation.visibleForTesting
int? isoMicrosSinceEpoch(String s, {Map<int, int>? localOffsets}) {
  final n = s.length;
  int digits(int at, int count) {
    if (at + count > n) return -1;
    var v = 0;
    for (var i = at; i < at + count; i++) {
      final c = s.codeUnitAt(i) - 0x30;
      if (c < 0 || c > 9) return -1;
      v = v * 10 + c;
    }
    return v;
  }

  if (n < 10 || s.codeUnitAt(4) != 0x2D || s.codeUnitAt(7) != 0x2D) {
    return null;
  }
  final year = digits(0, 4);
  final month = digits(5, 2);
  final day = digits(8, 2);
  if (year < 0 || month < 0 || day < 0) return null;
  var hour = 0, minute = 0, second = 0, milli = 0, micro = 0;
  var i = 10;
  if (i < n) {
    final sep = s.codeUnitAt(i);
    // `T` or a space, as DateTime.parse takes; a lower-case `t` it does not.
    if (sep != 0x54 && sep != 0x20) return null;
    hour = digits(i + 1, 2);
    if (hour < 0 || i + 3 >= n || s.codeUnitAt(i + 3) != 0x3A) return null;
    minute = digits(i + 4, 2);
    if (minute < 0) return null;
    i += 6;
    if (i < n && s.codeUnitAt(i) == 0x3A) {
      second = digits(i + 1, 2);
      if (second < 0) return null;
      i += 3;
      if (i < n && s.codeUnitAt(i) == 0x2E) {
        i++;
        final start = i;
        var fraction = 0;
        while (i < n) {
          final c = s.codeUnitAt(i) - 0x30;
          if (c < 0 || c > 9) break;
          if (i - start < 6) fraction = fraction * 10 + c;
          i++;
        }
        if (i == start) return null;
        for (var k = i - start; k < 6; k++) {
          fraction *= 10;
        }
        milli = fraction ~/ 1000;
        micro = fraction % 1000;
      }
    }
  }
  if (i == n) {
    if (localOffsets != null) {
      final wall = DateTime.utc(
          year, month, day, hour, minute, second, milli, micro);
      final key = wall.year * 10000 + wall.month * 100 + wall.day;
      final offset = localOffsets[key] ??=
          _dayOffsetMicros(wall.year, wall.month, wall.day);
      if (offset != _offsetChangesThatDay) {
        return wall.microsecondsSinceEpoch - offset;
      }
    }
    return DateTime(year, month, day, hour, minute, second, milli, micro)
        .microsecondsSinceEpoch;
  }
  var offsetMinutes = 0;
  final z = s.codeUnitAt(i);
  if (z == 0x5A || z == 0x7A) {
    if (i + 1 != n) return null;
  } else if (z == 0x2B || z == 0x2D) {
    final hh = digits(i + 1, 2);
    if (hh < 0) return null;
    i += 3;
    var mm = 0;
    if (i < n) {
      if (s.codeUnitAt(i) == 0x3A) i++;
      mm = digits(i, 2);
      if (mm < 0 || i + 2 != n) return null;
    }
    offsetMinutes = (hh * 60 + mm) * (z == 0x2D ? -1 : 1);
  } else {
    return null;
  }
  return DateTime.utc(year, month, day, hour, minute, second, milli, micro)
          .microsecondsSinceEpoch -
      offsetMinutes * Duration.microsecondsPerMinute;
}

const int _offsetChangesThatDay = 1 << 62;

/// The local zone's offset (µs) on that day, or [_offsetChangesThatDay] when
/// it is not the same at the first and the last second of the day.
int _dayOffsetMicros(int year, int month, int day) {
  final start = DateTime(year, month, day).timeZoneOffset;
  final end = DateTime(year, month, day, 23, 59, 59).timeZoneOffset;
  return start == end ? start.inMicroseconds : _offsetChangesThatDay;
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
  final localOffsets = <int, int>{};

  final keys = List<_SortKey>.generate(n, (i) {
    final row = rows[i];
    final val = columnIndex < row.length ? row[columnIndex] : '';
    return _SortKey.parse(val, localOffsets);
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
