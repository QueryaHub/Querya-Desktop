import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/compact_result_dataset.dart';
import 'package:querya_desktop/core/database/result_columns_builder.dart';

CompactColumnKind _expectedKind(List<Object?> col) {
  final cells = col.whereType<Object>().toList();
  if (cells.isEmpty) return CompactColumnKind.string;
  if (cells.every((v) => v is int)) return CompactColumnKind.int64;
  if (cells.every((v) => v is num)) return CompactColumnKind.float64;
  if (cells.every((v) => v is String)) return CompactColumnKind.string;
  return CompactColumnKind.generic;
}

Object? _expectedRaw(CompactColumnKind kind, Object? v) {
  if (v == null) return null;
  return kind == CompactColumnKind.float64 ? (v as num).toDouble() : v;
}

void main() {
  CompactResultDataset build(List<String> names, List<List<Object?>> rows,
      {String Function(Object?, int)? formatter}) {
    final b = ResultColumnsBuilder(names, cellFormatter: formatter);
    for (final r in rows) {
      b.addRow(r);
    }
    return b.build();
  }

  test('each column gets the kind its values call for, with its raw values', () {
    final rows = [
      [1, 1.5, 'a', 1, null, 'x'],
      [2, 2, 'b', 'two', null, 'y'],
      [null, null, null, 3.5, null, 7],
      [4, 0.25, 'd', null, null, null],
    ];
    final d = build(['i', 'f', 's', 'mix', 'nulls', 'm2'], rows);
    expect([for (final c in d.columns) c.kind], [
      CompactColumnKind.int64,
      CompactColumnKind.float64,
      CompactColumnKind.string,
      CompactColumnKind.generic,
      CompactColumnKind.string,
      CompactColumnKind.generic,
    ]);
    expect(d.rowCount, 4);
    // A float column holds its ints as doubles.
    expect(d.rawCellAt(1, 1), 2.0);
    // A generic column keeps its ints as ints and its doubles as doubles.
    expect(d.rawCellAt(0, 3), 1);
    expect(d.rawCellAt(0, 3), isA<int>());
    expect(d.rawCellAt(2, 3), 3.5);
    expect(d.rawCellAt(1, 3), 'two');
    expect(d.rawCellAt(2, 0), isNull);
    expect(d.cellAt(2, 0), 'NULL');
  });

  test('a late value that does not fit demotes the whole column', () {
    final rows = [
      for (var i = 0; i < 700; i++) [i],
      ['late'],
    ];
    final d = build(['c'], rows);
    expect(d.columns.single.kind, CompactColumnKind.generic);
    expect(d.rowCount, 701);
    expect(d.rawCellAt(0, 0), 0);
    expect(d.rawCellAt(699, 0), 699);
    expect(d.rawCellAt(700, 0), 'late');
  });

  test('ints that meet a double late become a float64 column', () {
    final rows = [
      for (var i = 0; i < 300; i++) [i],
      [0.5],
    ];
    final d = build(['c'], rows);
    expect(d.columns.single.kind, CompactColumnKind.float64);
    expect(d.rawCellAt(299, 0), 299.0);
    expect(d.rawCellAt(300, 0), 0.5);
  });

  test('a short row is padded with NULLs', () {
    final d = build(['a', 'b'], [
      [1, 'x'],
      [2],
    ]);
    expect(d.rawCellAt(1, 1), isNull);
    expect(d.columns[1].kind, CompactColumnKind.string);
  });

  test('cell by cell gives the same dataset as whole rows', () {
    final rows = [
      [1, 'a', null],
      [2, null, 3.5],
    ];
    final whole = build(['x', 'y', 'z'], rows);
    final b = ResultColumnsBuilder(['x', 'y', 'z']);
    for (final r in rows) {
      for (var i = 0; i < r.length; i++) {
        b.addCell(i, r[i]);
      }
      b.endRow();
    }
    final cells = b.build();
    for (var r = 0; r < 2; r++) {
      expect(cells.rawRow(r), whole.rawRow(r));
    }
  });

  test('the driver formatter decides: values it prints differently stay generic',
      () {
    // A "boolean" column: ints that print as true/false.
    String fmt(Object? v, int col) =>
        col == 0 ? (v == 1 ? 'true' : 'false') : '$v';
    final d = build(['flag', 'n'], [
      [1, 5],
      [0, 6],
    ], formatter: fmt);
    expect(d.columns[0].kind, CompactColumnKind.generic);
    expect(d.columns[1].kind, CompactColumnKind.int64);
    expect(d.cellAt(0, 0), 'true');
    expect(d.cellAt(1, 0), 'false');
  });

  test('nothing but NULLs is a string column; no rows is an empty dataset', () {
    expect(build(['a'], [[null], [null]]).columns.single.kind,
        CompactColumnKind.string);
    final empty = build(['a'], []);
    expect(empty.rowCount, 0);
    expect(empty.columns, isEmpty);
  });

  test('random columns agree with the kind and values the rules give', () {
    final rnd = Random(1552);
    Object? pick(int family) {
      if (rnd.nextInt(6) == 0) return null;
      switch (family) {
        case 0:
          return rnd.nextInt(1000) - 500;
        case 1:
          return rnd.nextBool() ? rnd.nextInt(100) : rnd.nextDouble() * 10;
        case 2:
          return 's${rnd.nextInt(50)}';
        default:
          return switch (rnd.nextInt(3)) {
            0 => rnd.nextInt(100),
            1 => 's${rnd.nextInt(9)}',
            _ => rnd.nextDouble(),
          };
      }
    }

    for (var trial = 0; trial < 150; trial++) {
      final family = rnd.nextInt(4);
      final n = 1 + rnd.nextInt(700);
      final col = [for (var i = 0; i < n; i++) pick(family)];
      final d = build(['c'], [for (final v in col) [v]]);
      final kind = _expectedKind(col);
      expect(d.columns.single.kind, kind, reason: 'trial $trial');
      for (var i = 0; i < n; i++) {
        expect(d.rawCellAt(i, 0), _expectedRaw(kind, col[i]),
            reason: 'trial $trial row $i');
      }
    }
  });
}
