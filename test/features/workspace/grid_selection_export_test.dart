import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid/grid_selection_manager.dart';

void main() {
  group('ResultGridSelection clipboard export (#1524)', () {
    const columns = ['x', 'y', 'z'];
    const rows = [
      ['a', 'b c', 'd,e'],
      ['1', '', '"q"'],
    ];
    const all = ResultGridSelection(
      startRow: 0,
      startColumn: 0,
      endRow: 1,
      endColumn: 2,
    );

    test('CSV: header, quoting and row order', () {
      expect(
        all.toCsv(rows, columns: columns),
        'x,y,z\na,b c,"d,e"\n1,,"""q"""',
      );
      expect(all.toCsv(rows), 'a,b c,"d,e"\n1,,"""q"""');
    });

    test('TSV: header, quoting and row order', () {
      expect(
        all.toTsv(rows, columns: columns),
        'x\ty\tz\na\tb c\td,e\n1\t\t"""q"""',
      );
      expect(all.toTsv(rows), 'a\tb c\td,e\n1\t\t"""q"""');
    });

    test('a column sub-range and rows past the end', () {
      const sub = ResultGridSelection(
        startRow: 1,
        startColumn: 1,
        endRow: 5,
        endColumn: 3,
      );
      // Column 3 does not exist: an empty cell; row 5 does not exist: skipped.
      expect(sub.toCsv(rows, columns: columns), 'y,z,\n,"""q""",');
      expect(sub.toTsv(rows), '\t"""q"""');
    });

    test('trailing empty cells of the last row are trimmed in TSV only', () {
      const one = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 1,
      );
      const data = [
        ['a', ''],
      ];
      expect(one.toTsv(data), 'a');
      expect(one.toCsv(data), 'a,');
    });

    test('empty input gives an empty string', () {
      expect(all.toCsv(const []), '');
      expect(all.toTsv(const []), '');
    });

    test('JSON keeps leading zeros, nulls and booleans', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 0,
        endColumn: 9,
      );
      final json = sel.toJson(
        ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j'],
        const [
          ['007', '12', '1.5', 'NULL', 'true', 'FALSE', 'x', ' 007 ', '0', '0.5'],
        ],
      );
      expect(jsonDecode(json), {
        'a': '007',
        'b': 12,
        'c': 1.5,
        'd': null,
        'e': true,
        'f': false,
        'g': 'x',
        'h': ' 007 ',
        'i': 0,
        'j': 0.5,
      });
    });

    test('JSON of several rows is an array', () {
      const sel = ResultGridSelection(
        startRow: 0,
        startColumn: 0,
        endRow: 1,
        endColumn: 0,
      );
      final json = sel.toJson(
        ['n'],
        const [
          ['1'],
          ['2'],
        ],
      );
      expect(jsonDecode(json), [
        {'n': 1},
        {'n': 2},
      ]);
    });
  });
}
