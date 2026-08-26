import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/compact_result_dataset.dart';

void main() {
  group('CompactResultDataset', () {
    test('packs typed columns into specialized compact columnar buffers', () {
      final columns = ['id', 'amount', 'status', 'meta'];
      final rows = <List<Object?>>[
        [1, 19.99, 'active', {'role': 'admin'}],
        [2, 49.50, 'pending', null],
        [3, null, 'active', {'role': 'user'}],
        [null, 0.0, null, null],
      ];

      final dataset = CompactResultDataset.fromRawRows(columns, rows);

      expect(dataset.rowCount, 4);
      expect(dataset.columnCount, 4);
      expect(dataset.columns[0].kind, CompactColumnKind.int64);
      expect(dataset.columns[1].kind, CompactColumnKind.float64);
      expect(dataset.columns[2].kind, CompactColumnKind.string);
      expect(dataset.columns[3].kind, CompactColumnKind.generic);

      // Raw value tests
      expect(dataset.rawCellAt(0, 0), 1);
      expect(dataset.rawCellAt(0, 1), 19.99);
      expect(dataset.rawCellAt(0, 2), 'active');
      expect(dataset.rawCellAt(0, 3), {'role': 'admin'});

      // Null handling
      expect(dataset.rawCellAt(2, 1), isNull);
      expect(dataset.rawCellAt(3, 0), isNull);
      expect(dataset.rawCellAt(3, 2), isNull);

      // Stringified lazy cells
      expect(dataset.cellAt(0, 0), '1');
      expect(dataset.cellAt(0, 1), '19.99');
      expect(dataset.cellAt(0, 2), 'active');
      expect(dataset.cellAt(2, 1), 'NULL');
      expect(dataset.cellAt(3, 0), 'NULL');
      expect(dataset.cellAt(3, 2), 'NULL');
      expect(dataset.cellAt(3, 1), '0');
    });

    test('asLazyRowList provides transparent List<List<String>> indexable interface', () {
      final columns = ['code', 'count'];
      final rows = <List<Object?>>[
        ['alpha', 10],
        ['beta', 25],
        ['gamma', null],
      ];

      final dataset = CompactResultDataset.fromRawRows(columns, rows);
      final lazyRows = dataset.asLazyRowList();

      expect(lazyRows.length, 3);
      expect(lazyRows[0].length, 2);
      expect(lazyRows[0][0], 'alpha');
      expect(lazyRows[0][1], '10');
      expect(lazyRows[1][0], 'beta');
      expect(lazyRows[1][1], '25');
      expect(lazyRows[2][0], 'gamma');
      expect(lazyRows[2][1], 'NULL');

      expect(() => lazyRows[0][0] = 'modified', throwsUnsupportedError);
      expect(() => lazyRows.add(['delta', '50']), throwsUnsupportedError);
    });

    test('handles empty dataset gracefully', () {
      final dataset = CompactResultDataset.fromRawRows(['id', 'name'], []);
      expect(dataset.rowCount, 0);
      expect(dataset.asLazyRowList(), isEmpty);
    });

    test('100,000-row benchmark verifies packing throughput and fast viewport slicing', () {
      final columns = ['id', 'user_id', 'balance', 'status', 'flag'];
      final statuses = ['active', 'inactive', 'suspended', 'trial'];

      final rawData = List<List<Object?>>.generate(
        100000,
        (i) => [
          i + 1,
          (i * 3) % 10000,
          (i % 100) * 1.5,
          statuses[i % statuses.length],
          i % 2 == 0 ? 1 : 0,
        ],
      );

      final packStopwatch = Stopwatch()..start();
      final dataset = CompactResultDataset.fromRawRows(columns, rawData);
      packStopwatch.stop();

      expect(dataset.rowCount, 100000);
      expect(packStopwatch.elapsedMilliseconds, lessThan(300));

      final lazyRows = dataset.asLazyRowList();

      // Viewport simulation: slice 50 rows x 5 columns
      final viewportStopwatch = Stopwatch()..start();
      final viewportSlice = <List<String>>[];
      for (var r = 50000; r < 50050; r++) {
        final row = <String>[];
        for (var c = 0; c < 5; c++) {
          row.add(lazyRows[r][c]);
        }
        viewportSlice.add(row);
      }
      viewportStopwatch.stop();

      expect(viewportSlice.length, 50);
      expect(viewportStopwatch.elapsedMilliseconds, lessThan(5));
      expect(viewportSlice[0][0], '50001');
      expect(viewportSlice[0][3], 'active');
    });
  });
}
