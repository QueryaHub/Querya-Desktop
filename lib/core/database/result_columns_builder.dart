import 'dart:typed_data';

import 'compact_result_dataset.dart';
import 'result_row_string_convert.dart';

/// Builds a [CompactResultDataset] while a driver delivers the rows, without
/// first keeping a `List<List<Object?>>` of the whole result (#1552).
///
/// A column's kind is what [CompactResultDataset.fromRawRows] always decided:
/// all ints is int64, all numbers float64, all strings string, nothing
/// (all NULL) string, anything else generic. Here that is learnt as values
/// arrive, so a column can be demoted late: ints stay in the int64 buffer and
/// doubles go to a second buffer, so a column that ends up generic still holds
/// its ints as ints.
///
/// [cellFormatter] is the driver's display formatter; the first
/// [formattedSamples] non-null cells of a column go through it to see whether
/// the column prints as its values do (bytea, boolean, ...).
class ResultColumnsBuilder {
  ResultColumnsBuilder(
    this.columnNames, {
    this.cellFormatter,
    StringInternPool? pool,
  })  : pool = pool ?? StringInternPool(),
        _columns = [
          for (var i = 0; i < columnNames.length; i++) _ColumnBuilder(i),
        ];

  /// Non-null cells per column checked against the formatter (#1548).
  static const formattedSamples = 60;

  final List<String> columnNames;
  final String Function(Object? value, int colIndex)? cellFormatter;
  final StringInternPool pool;
  final List<_ColumnBuilder> _columns;

  int _rows = 0;

  int get rowCount => _rows;

  /// Adds one row. A short row is padded with NULLs.
  void addRow(List<Object?> row) {
    final n = _columns.length;
    for (var i = 0; i < n; i++) {
      _columns[i].add(i < row.length ? row[i] : null, cellFormatter);
    }
    _rows++;
  }

  /// Adds one row cell by cell: call [addCell] for every column in order, then
  /// [endRow]. For drivers whose rows are not lists.
  void addCell(int col, Object? value) =>
      _columns[col].add(value, cellFormatter);

  void endRow() => _rows++;

  CompactResultDataset build() {
    if (_rows == 0 || _columns.isEmpty) {
      return CompactResultDataset(
        columnNames: columnNames,
        columns: const [],
        rowCount: 0,
        pool: pool,
      );
    }
    return CompactResultDataset(
      columnNames: columnNames,
      columns: [
        for (final c in _columns)
          c.finish(_rows, pool, cellFormatter == null
              ? null
              : (v) => cellFormatter!(v, c.index)),
      ],
      rowCount: _rows,
      pool: pool,
    );
  }
}

enum _Mode { empty, numeric, string, generic }

class _ColumnBuilder {
  _ColumnBuilder(this.index);

  final int index;

  var _mode = _Mode.empty;
  var _allInt = true;
  var _allFloat = true;
  var _allString = true;
  var _nonNull = 0;
  var _length = 0;

  // numeric: ints in [_ints], doubles in [_doubles] where [_isDouble] has the
  // bit; [_nulls] has a bit per NULL row (also kept while empty).
  var _capacity = 0;
  var _ints = Int64List(0);
  Float64List? _doubles;
  Uint8List? _isDouble;
  var _nulls = Uint8List(0);

  // string / generic
  List<String?> _strings = <String?>[];
  List<Object?> _objects = <Object?>[];

  void add(Object? value, String Function(Object?, int)? formatter) {
    if (value == null) {
      _addNull();
      _length++;
      return;
    }
    _nonNull++;
    // The driver formatters print a column's ints, numbers and strings by the
    // column's type, not by the value, so the first cells show whether the
    // column prints as its values do. Past those, only the type is tested.
    if (formatter != null && _nonNull <= ResultColumnsBuilder.formattedSamples) {
      final formatted = formatter(value, index);
      if (_allInt && (value is! int || formatted != value.toString())) {
        _allInt = false;
      }
      if (_allFloat && (value is! num || formatted != value.toString())) {
        _allFloat = false;
      }
      if (_allString && (value is! String || formatted != value)) {
        _allString = false;
      }
    } else {
      if (_allInt && value is! int) _allInt = false;
      if (_allFloat && value is! num) _allFloat = false;
      if (_allString && value is! String) _allString = false;
    }

    final target = !_allInt && !_allFloat && !_allString
        ? _Mode.generic
        : _allString
            ? _Mode.string
            : _Mode.numeric;
    if (_mode != target) _switchTo(target);

    switch (_mode) {
      case _Mode.numeric:
        _ensureCapacity();
        if (value is int) {
          _ints[_length] = value;
        } else {
          final number = value as num;
          _doubles ??= Float64List(_capacity);
          _isDouble ??= Uint8List((_capacity + 7) >> 3);
          _doubles![_length] = number.toDouble();
          _isDouble![_length >> 3] |= 1 << (_length & 7);
        }
      case _Mode.string:
        _strings.add(value as String);
      case _Mode.generic:
        _objects.add(value);
      case _Mode.empty:
        break;
    }
    _length++;
  }

  void _addNull() {
    switch (_mode) {
      case _Mode.empty:
      case _Mode.numeric:
        _ensureCapacity();
        _nulls[_length >> 3] |= 1 << (_length & 7);
      case _Mode.string:
        _strings.add(null);
      case _Mode.generic:
        _objects.add(null);
    }
  }

  void _ensureCapacity() {
    if (_length < _capacity) return;
    final grown = _capacity == 0 ? 256 : _capacity * 2;
    _ints = _grow64(_ints, grown);
    if (_doubles != null) _doubles = _growF(_doubles!, grown);
    if (_isDouble != null) _isDouble = _growBytes(_isDouble!, (grown + 7) >> 3);
    _nulls = _growBytes(_nulls, (grown + 7) >> 3);
    _capacity = grown;
  }

  static Int64List _grow64(Int64List a, int n) => Int64List(n)..setAll(0, a);
  static Float64List _growF(Float64List a, int n) =>
      Float64List(n)..setAll(0, a);
  static Uint8List _growBytes(Uint8List a, int n) =>
      Uint8List(n)..setAll(0, a);

  bool _isNullRow(int i) => (_nulls[i >> 3] & (1 << (i & 7))) != 0;

  Object? _numericAt(int i) {
    if (_isNullRow(i)) return null;
    final dbl = _isDouble;
    if (dbl != null && (dbl[i >> 3] & (1 << (i & 7))) != 0) {
      return _doubles![i];
    }
    return _ints[i];
  }

  /// Moves what was stored so far into the storage of [target].
  void _switchTo(_Mode target) {
    final from = _mode;
    _mode = target;
    switch (target) {
      case _Mode.numeric:
        // Only from empty: the rows so far are NULLs, already in the bitmap.
        break;
      case _Mode.string:
        // Only from empty.
        _strings = List<String?>.filled(_length, null, growable: true);
      case _Mode.generic:
        if (from == _Mode.string) {
          _objects = List<Object?>.of(_strings, growable: true);
          _strings = <String?>[];
        } else if (from == _Mode.numeric) {
          _objects = [for (var i = 0; i < _length; i++) _numericAt(i)];
          _releaseNumeric();
        } else {
          _objects = List<Object?>.filled(_length, null, growable: true);
        }
      case _Mode.empty:
        break;
    }
  }

  void _releaseNumeric() {
    _capacity = 0;
    _ints = Int64List(0);
    _doubles = null;
    _isDouble = null;
    _nulls = Uint8List(0);
  }

  CompactColumn finish(
    int rows,
    StringInternPool pool,
    String Function(Object?)? formatter,
  ) {
    // Rows a column never saw (a short last row) are NULLs.
    while (_length < rows) {
      _addNull();
      _length++;
    }
    final bitmapBytes = (rows + 7) >> 3;
    if (_nonNull == 0) {
      return StringCompactColumn(
        values: List<String?>.filled(rows, null),
        length: rows,
      );
    }
    if (_mode == _Mode.numeric) {
      final nulls = Uint8List.fromList(Uint8List.sublistView(_nulls, 0, bitmapBytes));
      if (_allInt) {
        return Int64CompactColumn(
          values: Int64List.fromList(Int64List.sublistView(_ints, 0, rows)),
          nullBitmap: nulls,
          length: rows,
        );
      }
      // Numbers of both kinds: all float64.
      final values = Float64List(rows);
      final dbl = _isDouble;
      for (var i = 0; i < rows; i++) {
        if (_isNullRow(i)) continue;
        values[i] = dbl != null && (dbl[i >> 3] & (1 << (i & 7))) != 0
            ? _doubles![i]
            : _ints[i].toDouble();
      }
      return Float64CompactColumn(
        values: values,
        nullBitmap: nulls,
        length: rows,
      );
    }
    if (_mode == _Mode.string) {
      return StringCompactColumn(
        values: [
          for (final s in _strings) s == null ? null : pool.intern(s),
        ],
        length: rows,
      );
    }
    return GenericCompactColumn(
      values: _objects,
      length: rows,
      formatter: formatter,
    );
  }
}
