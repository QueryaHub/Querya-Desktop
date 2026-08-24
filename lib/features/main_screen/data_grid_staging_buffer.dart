import 'package:flutter/foundation.dart';

/// Status of a row within the staging buffer.
enum StagedRowStatus {
  unchanged,
  modified,
  inserted,
  deleted,
}

/// Status of an individual cell.
enum StagedCellStatus {
  clean,
  modified,
}

/// In-memory staging buffer for interactive table data edits.
///
/// Keeps original data intact and tracks staged changes (modified cells,
/// newly inserted rows, and rows marked for deletion). Notifies listeners
/// on any mutation so the UI (VirtualResultGrid, toolbar) updates reactively.
class DataGridStagingBuffer extends ChangeNotifier {
  DataGridStagingBuffer({
    required List<String> columns,
    required List<List<String>> rows,
  })  : _originalColumns = List.unmodifiable(columns),
        _originalRows = List.unmodifiable(
          rows.map((r) => List<String>.unmodifiable(r)).toList(),
        );

  final List<String> _originalColumns;
  final List<List<String>> _originalRows;

  /// Map of `rowIndex -> (colIndex -> stagedValue)` for modified cells in baseline rows.
  final Map<int, Map<int, String>> _modifiedCells = {};

  /// Rows appended as new records.
  final List<List<String>> _insertedRows = [];

  /// Baseline row indices marked for deletion.
  final Set<int> _deletedRowIndices = {};

  List<String> get columns => _originalColumns;
  List<List<String>> get originalRows => _originalRows;

  /// Total number of visible rows (baseline + inserted).
  int get totalRowCount => _originalRows.length + _insertedRows.length;

  /// True if there are any pending edits, insertions, or deletions.
  bool get isDirty =>
      _modifiedCells.isNotEmpty ||
      _insertedRows.isNotEmpty ||
      _deletedRowIndices.isNotEmpty;

  /// Total count of staged modifications (modified cells + inserted rows + deleted rows).
  int get changeCount {
    var cellCount = 0;
    for (final colMap in _modifiedCells.values) {
      cellCount += colMap.length;
    }
    return cellCount + _insertedRows.length + _deletedRowIndices.length;
  }

  /// Number of baseline rows marked for deletion.
  int get deletedRowCount => _deletedRowIndices.length;

  /// Number of newly inserted rows.
  int get insertedRowCount => _insertedRows.length;

  /// Number of modified cells in baseline rows.
  int get modifiedCellCount {
    var count = 0;
    for (final colMap in _modifiedCells.values) {
      count += colMap.length;
    }
    return count;
  }

  /// Returns the current effective cell value.
  String getCellValue(int row, int col) {
    if (row < 0 || col < 0) return '';
    if (row < _originalRows.length) {
      final staged = _modifiedCells[row]?[col];
      if (staged != null) return staged;
      if (col < _originalRows[row].length) {
        return _originalRows[row][col];
      }
      return '';
    }
    final insertIdx = row - _originalRows.length;
    if (insertIdx < _insertedRows.length && col < _insertedRows[insertIdx].length) {
      return _insertedRows[insertIdx][col];
    }
    return '';
  }

  /// Returns original baseline cell value, or null if row is inserted.
  String? getOriginalCellValue(int row, int col) {
    if (row >= 0 && row < _originalRows.length && col >= 0 && col < _originalRows[row].length) {
      return _originalRows[row][col];
    }
    return null;
  }

  /// Returns the status of the specified row.
  StagedRowStatus getRowStatus(int row) {
    if (row < 0) return StagedRowStatus.unchanged;
    if (row >= _originalRows.length) {
      return StagedRowStatus.inserted;
    }
    if (_deletedRowIndices.contains(row)) {
      return StagedRowStatus.deleted;
    }
    if (_modifiedCells.containsKey(row) && _modifiedCells[row]!.isNotEmpty) {
      return StagedRowStatus.modified;
    }
    return StagedRowStatus.unchanged;
  }

  /// Returns the status of the specified cell.
  StagedCellStatus getCellStatus(int row, int col) {
    if (row >= 0 && row < _originalRows.length) {
      if (_modifiedCells[row]?.containsKey(col) == true) {
        return StagedCellStatus.modified;
      }
    }
    return StagedCellStatus.clean;
  }

  /// Stages an edit for the specified cell.
  /// If the new value equals original value, clears the modified flag.
  void setCell(int row, int col, String value) {
    if (row < 0 || col < 0) return;

    if (row < _originalRows.length) {
      final orig = col < _originalRows[row].length ? _originalRows[row][col] : '';
      if (value == orig) {
        if (_modifiedCells.containsKey(row)) {
          _modifiedCells[row]!.remove(col);
          if (_modifiedCells[row]!.isEmpty) {
            _modifiedCells.remove(row);
          }
          notifyListeners();
        }
      } else {
        final rowMap = _modifiedCells.putIfAbsent(row, () => <int, String>{});
        if (rowMap[col] != value) {
          rowMap[col] = value;
          notifyListeners();
        }
      }
    } else {
      final insertIdx = row - _originalRows.length;
      if (insertIdx < _insertedRows.length) {
        while (_insertedRows[insertIdx].length <= col) {
          _insertedRows[insertIdx].add('');
        }
        if (_insertedRows[insertIdx][col] != value) {
          _insertedRows[insertIdx][col] = value;
          notifyListeners();
        }
      }
    }
  }

  /// Appends a new empty or pre-filled row.
  int addRow([List<String>? initialValues]) {
    final row = initialValues != null
        ? List<String>.from(initialValues)
        : List<String>.filled(_originalColumns.length, '');
    _insertedRows.add(row);
    notifyListeners();
    return totalRowCount - 1;
  }

  /// Removes an inserted row at the given absolute row index.
  void removeInsertedRow(int row) {
    final insertIdx = row - _originalRows.length;
    if (insertIdx >= 0 && insertIdx < _insertedRows.length) {
      _insertedRows.removeAt(insertIdx);
      notifyListeners();
    }
  }

  /// Marks a baseline row as deleted, or removes an inserted row.
  void toggleDeleteRow(int row) {
    if (row < 0) return;
    if (row < _originalRows.length) {
      if (_deletedRowIndices.contains(row)) {
        _deletedRowIndices.remove(row);
      } else {
        _deletedRowIndices.add(row);
      }
      notifyListeners();
    } else {
      removeInsertedRow(row);
    }
  }

  /// Reverts changes for a single cell back to baseline.
  void revertCell(int row, int col) {
    if (row < _originalRows.length && _modifiedCells.containsKey(row)) {
      if (_modifiedCells[row]!.remove(col) != null) {
        if (_modifiedCells[row]!.isEmpty) {
          _modifiedCells.remove(row);
        }
        notifyListeners();
      }
    }
  }

  /// Reverts all modifications or deletion for a given row.
  void revertRow(int row) {
    if (row < 0) return;
    if (row < _originalRows.length) {
      var changed = false;
      if (_modifiedCells.remove(row) != null) changed = true;
      if (_deletedRowIndices.remove(row)) changed = true;
      if (changed) notifyListeners();
    } else {
      removeInsertedRow(row);
    }
  }

  /// Reverts all staged changes and resets buffer to clean baseline.
  void revertAll() {
    if (!isDirty) return;
    _modifiedCells.clear();
    _insertedRows.clear();
    _deletedRowIndices.clear();
    notifyListeners();
  }

  /// Returns the full list of effective rows (original with modifications applied + inserted rows).
  List<List<String>> get effectiveRows {
    final result = <List<String>>[];
    for (var r = 0; r < _originalRows.length; r++) {
      final row = List<String>.from(_originalRows[r]);
      final mods = _modifiedCells[r];
      if (mods != null) {
        for (final entry in mods.entries) {
          if (entry.key < row.length) {
            row[entry.key] = entry.value;
          }
        }
      }
      result.add(row);
    }
    for (final ins in _insertedRows) {
      result.add(List<String>.from(ins));
    }
    return result;
  }
}
