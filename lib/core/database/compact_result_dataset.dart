import 'dart:collection';
import 'dart:typed_data';

import 'result_row_string_convert.dart';

/// Supported compact column storage kinds.
enum CompactColumnKind {
  int64,
  float64,
  string,
  generic,
}

/// Columnar storage interface for a single database column in a result set.
sealed class CompactColumn {
  int get length;
  CompactColumnKind get kind;
  Object? rawValueAt(int index);
  String stringValueAt(int index, [StringInternPool? pool]);
  bool isNull(int index);
}

/// Compact 64-bit integer column backed by [Int64List] and a packed null bitmap.
class Int64CompactColumn implements CompactColumn {
  Int64CompactColumn({
    required this.values,
    required this.nullBitmap,
    required this.length,
  });

  final Int64List values;
  final Uint8List nullBitmap; // 1 bit per row indicates null
  @override
  final int length;

  @override
  CompactColumnKind get kind => CompactColumnKind.int64;

  @override
  bool isNull(int index) {
    final byteIndex = index >> 3;
    final bitOffset = index & 7;
    return (nullBitmap[byteIndex] & (1 << bitOffset)) != 0;
  }

  @override
  Object? rawValueAt(int index) {
    if (isNull(index)) return null;
    return values[index];
  }

  @override
  String stringValueAt(int index, [StringInternPool? pool]) {
    if (isNull(index)) return 'NULL';
    final val = values[index];
    if (val >= 0 && val <= 10 && pool != null) {
      return pool.internObject(val);
    }
    return val.toString();
  }
}

/// Compact 64-bit float column backed by [Float64List] and a packed null bitmap.
class Float64CompactColumn implements CompactColumn {
  Float64CompactColumn({
    required this.values,
    required this.nullBitmap,
    required this.length,
  });

  final Float64List values;
  final Uint8List nullBitmap;
  @override
  final int length;

  @override
  CompactColumnKind get kind => CompactColumnKind.float64;

  @override
  bool isNull(int index) {
    final byteIndex = index >> 3;
    final bitOffset = index & 7;
    return (nullBitmap[byteIndex] & (1 << bitOffset)) != 0;
  }

  @override
  Object? rawValueAt(int index) {
    if (isNull(index)) return null;
    return values[index];
  }

  @override
  String stringValueAt(int index, [StringInternPool? pool]) {
    if (isNull(index)) return 'NULL';
    final val = values[index];
    if (val == val.toInt() && !val.isNaN && !val.isInfinite) {
      return val.toInt().toString();
    }
    return val.toString();
  }
}

/// String column backed by interned String references.
class StringCompactColumn implements CompactColumn {
  StringCompactColumn({
    required this.values,
    required this.length,
  });

  final List<String?> values;
  @override
  final int length;

  @override
  CompactColumnKind get kind => CompactColumnKind.string;

  @override
  bool isNull(int index) => values[index] == null;

  @override
  Object? rawValueAt(int index) => values[index];

  @override
  String stringValueAt(int index, [StringInternPool? pool]) {
    final val = values[index];
    if (val == null) return 'NULL';
    return pool != null ? pool.intern(val) : val;
  }
}

/// Generic object column for composite or unparsed database types.
class GenericCompactColumn implements CompactColumn {
  GenericCompactColumn({
    required this.values,
    required this.length,
  });

  final List<Object?> values;
  @override
  final int length;

  @override
  CompactColumnKind get kind => CompactColumnKind.generic;

  @override
  bool isNull(int index) => values[index] == null;

  @override
  Object? rawValueAt(int index) => values[index];

  @override
  String stringValueAt(int index, [StringInternPool? pool]) {
    final val = values[index];
    if (val == null) return 'NULL';
    return pool != null ? pool.internObject(val) : val.toString();
  }
}

/// Memory-efficient columnar dataset for query result tables.
///
/// Converts numeric columns to contiguous primitive TypedData arrays
/// and lazily stringifies cells on-demand for viewport rendering,
/// eliminating the allocation of millions of intermediate String objects in heap.
class CompactResultDataset {
  CompactResultDataset({
    required this.columnNames,
    required this.columns,
    required this.rowCount,
    StringInternPool? pool,
  }) : pool = pool ?? StringInternPool();

  final List<String> columnNames;
  final List<CompactColumn> columns;
  final int rowCount;
  final StringInternPool pool;

  int get columnCount => columnNames.length;

  /// Returns the raw cell value (int, double, String, or null).
  Object? rawCellAt(int rowIndex, int colIndex) {
    if (colIndex < 0 || colIndex >= columns.length) return null;
    return columns[colIndex].rawValueAt(rowIndex);
  }

  /// Lazily stringifies the cell value at [rowIndex], [colIndex].
  String cellAt(int rowIndex, int colIndex) {
    if (colIndex < 0 || colIndex >= columns.length) return 'NULL';
    return columns[colIndex].stringValueAt(rowIndex, pool);
  }

  /// Returns a full row of formatted strings for [rowIndex].
  List<String> rowStrings(int rowIndex) {
    return [
      for (var col = 0; col < columns.length; col++)
        cellAt(rowIndex, col),
    ];
  }

  /// Returns a full row of raw typed values for [rowIndex].
  List<Object?> rawRow(int rowIndex) {
    return [
      for (var col = 0; col < columns.length; col++)
        rawCellAt(rowIndex, col),
    ];
  }

  /// Exposes a lazy, unmodifiable `List<List<String>>` row view that formats
  /// cells on-the-fly when indexed by viewport-based virtual grids.
  List<List<String>> asLazyRowList() => _LazyDatasetRowList(this);

  /// Constructs a [CompactResultDataset] from raw rows, detecting column types
  /// and packing numeric columns into [Int64List] / [Float64List].
  static CompactResultDataset fromRawRows(
    List<String> columnNames,
    List<List<Object?>> rawRows, {
    StringInternPool? pool,
  }) {
    final rowCount = rawRows.length;
    final colCount = columnNames.length;
    final internPool = pool ?? StringInternPool();

    if (rowCount == 0 || colCount == 0) {
      return CompactResultDataset(
        columnNames: columnNames,
        columns: const [],
        rowCount: 0,
        pool: internPool,
      );
    }

    // 1. Detect column types by inspecting non-null samples
    final kinds = List<CompactColumnKind>.filled(colCount, CompactColumnKind.generic);
    for (var col = 0; col < colCount; col++) {
      var allInt = true;
      var allFloat = true;
      var allString = true;
      var sampleCount = 0;

      for (var row = 0; row < rowCount; row++) {
        final val = rawRows[row].length > col ? rawRows[row][col] : null;
        if (val == null) continue;
        sampleCount++;

        if (val is! int) {
          allInt = false;
        }
        if (val is! num) {
          allFloat = false;
        }
        if (val is! String) {
          allString = false;
        }

        if (sampleCount >= 60 && !allInt && !allFloat && !allString) {
          break;
        }
      }

      if (sampleCount > 0) {
        if (allInt) {
          kinds[col] = CompactColumnKind.int64;
        } else if (allFloat) {
          kinds[col] = CompactColumnKind.float64;
        } else if (allString) {
          kinds[col] = CompactColumnKind.string;
        } else {
          kinds[col] = CompactColumnKind.generic;
        }
      } else {
        kinds[col] = CompactColumnKind.string;
      }
    }

    // 2. Allocate packed columnar buffers
    final compactColumns = <CompactColumn>[];
    final bitmapBytes = (rowCount + 7) >> 3;

    for (var col = 0; col < colCount; col++) {
      final kind = kinds[col];
      switch (kind) {
        case CompactColumnKind.int64:
          final values = Int64List(rowCount);
          final nullBitmap = Uint8List(bitmapBytes);
          for (var row = 0; row < rowCount; row++) {
            final val = rawRows[row].length > col ? rawRows[row][col] : null;
            if (val == null) {
              final byte = row >> 3;
              final bit = row & 7;
              nullBitmap[byte] |= (1 << bit);
            } else if (val is int) {
              values[row] = val;
            } else if (val is num) {
              values[row] = val.toInt();
            }
          }
          compactColumns.add(Int64CompactColumn(
            values: values,
            nullBitmap: nullBitmap,
            length: rowCount,
          ));

        case CompactColumnKind.float64:
          final values = Float64List(rowCount);
          final nullBitmap = Uint8List(bitmapBytes);
          for (var row = 0; row < rowCount; row++) {
            final val = rawRows[row].length > col ? rawRows[row][col] : null;
            if (val == null) {
              final byte = row >> 3;
              final bit = row & 7;
              nullBitmap[byte] |= (1 << bit);
            } else if (val is num) {
              values[row] = val.toDouble();
            }
          }
          compactColumns.add(Float64CompactColumn(
            values: values,
            nullBitmap: nullBitmap,
            length: rowCount,
          ));

        case CompactColumnKind.string:
          final values = List<String?>.filled(rowCount, null);
          for (var row = 0; row < rowCount; row++) {
            final val = rawRows[row].length > col ? rawRows[row][col] : null;
            if (val is String) {
              values[row] = internPool.intern(val);
            } else if (val != null) {
              values[row] = internPool.intern(val.toString());
            }
          }
          compactColumns.add(StringCompactColumn(
            values: values,
            length: rowCount,
          ));

        case CompactColumnKind.generic:
          final values = List<Object?>.filled(rowCount, null);
          for (var row = 0; row < rowCount; row++) {
            final val = rawRows[row].length > col ? rawRows[row][col] : null;
            values[row] = val;
          }
          compactColumns.add(GenericCompactColumn(
            values: values,
            length: rowCount,
          ));
      }
    }

    return CompactResultDataset(
      columnNames: columnNames,
      columns: compactColumns,
      rowCount: rowCount,
      pool: internPool,
    );
  }
}

class _LazyDatasetRowList extends ListBase<List<String>> {
  _LazyDatasetRowList(this.dataset);

  final CompactResultDataset dataset;

  @override
  int get length => dataset.rowCount;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Dataset rows are unmodifiable');

  @override
  List<String> operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return _LazyDatasetRow(dataset, index);
  }

  @override
  void operator []=(int index, List<String> value) =>
      throw UnsupportedError('Dataset rows are unmodifiable');
}

class _LazyDatasetRow extends ListBase<String> {
  _LazyDatasetRow(this.dataset, this.rowIndex);

  final CompactResultDataset dataset;
  final int rowIndex;

  @override
  int get length => dataset.columnCount;

  @override
  set length(int newLength) =>
      throw UnsupportedError('Row cells are unmodifiable');

  @override
  String operator [](int index) {
    RangeError.checkValidIndex(index, this, 'index', length);
    return dataset.cellAt(rowIndex, index);
  }

  @override
  void operator []=(int index, String value) =>
      throw UnsupportedError('Row cells are unmodifiable');
}
