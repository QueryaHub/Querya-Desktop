import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/compact_result_dataset.dart';
import 'package:querya_desktop/core/database/sql_query_runner.dart';

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
      expect(dataset.cellAt(3, 1), '0.0');
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

    test('Float64CompactColumn preserves decimal notation and floating-point precision', () {
      final columns = ['rate', 'measurement', 'edge_cases'];
      final rows = <List<Object?>>[
        [1.0, 100.0, 0.0],
        [42.0, -5.0, 3.141592653589793],
        [0.0001, -0.0, 1e10],
        [null, double.nan, double.infinity],
      ];

      final dataset = CompactResultDataset.fromRawRows(columns, rows);

      expect(dataset.columns[0].kind, CompactColumnKind.float64);
      expect(dataset.columns[1].kind, CompactColumnKind.float64);
      expect(dataset.columns[2].kind, CompactColumnKind.float64);

      expect(dataset.cellAt(0, 0), '1.0');
      expect(dataset.cellAt(0, 1), '100.0');
      expect(dataset.cellAt(0, 2), '0.0');

      expect(dataset.cellAt(1, 0), '42.0');
      expect(dataset.cellAt(1, 1), '-5.0');
      expect(dataset.cellAt(1, 2), '3.141592653589793');

      expect(dataset.cellAt(2, 0), '0.0001');
      expect(dataset.cellAt(2, 1), '-0.0');
      expect(dataset.cellAt(2, 2), '10000000000.0');

      expect(dataset.cellAt(3, 0), 'NULL');
      expect(dataset.cellAt(3, 1), 'NaN');
      expect(dataset.cellAt(3, 2), 'Infinity');
    });

    test('Float64CompactColumn stringValueAt preserves decimal point for whole numbers directly', () {
      final values = Float64List.fromList([1.0, 2.0, 0.0, 100.0]);
      final nullBitmap = Uint8List(1);
      final column = Float64CompactColumn(
        values: values,
        nullBitmap: nullBitmap,
        length: 4,
      );

      expect(column.stringValueAt(0), '1.0');
      expect(column.stringValueAt(1), '2.0');
      expect(column.stringValueAt(2), '0.0');
      expect(column.stringValueAt(3), '100.0');
    });

    test('fromRawRows with cellFormatter customizes generic column formatting and overrides primitives', () {
      final columns = ['id', 'is_active', 'raw_bytes'];
      final rows = <List<Object?>>[
        [101, 1, [0xde, 0xad]],
        [102, 0, [0xbe, 0xef]],
        [103, null, null],
      ];

      final dataset = CompactResultDataset.fromRawRows(
        columns,
        rows,
        cellFormatter: (val, colIndex) {
          if (colIndex == 1) {
            return val == 1 ? 'true' : (val == 0 ? 'false' : 'NULL');
          }
          if (colIndex == 2 && val is List<int>) {
            return '0x${val.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
          }
          return val.toString();
        },
      );

      expect(dataset.columns[0].kind, CompactColumnKind.int64);
      // is_active was 1 and 0, but cellFormatter returned 'true' / 'false' != '1' / '0',
      // so it was correctly recognized as generic with formatter
      expect(dataset.columns[1].kind, CompactColumnKind.generic);
      expect(dataset.columns[2].kind, CompactColumnKind.generic);

      expect(dataset.cellAt(0, 0), '101');
      expect(dataset.cellAt(0, 1), 'true');
      expect(dataset.cellAt(0, 2), '0xdead');

      expect(dataset.cellAt(1, 0), '102');
      expect(dataset.cellAt(1, 1), 'false');
      expect(dataset.cellAt(1, 2), '0xbeef');

      expect(dataset.cellAt(2, 0), '103');
      expect(dataset.cellAt(2, 1), 'NULL');
      expect(dataset.cellAt(2, 2), 'NULL');
    });

    test('SqlExecutionResult.fromDataset provides transparent lazy rows and backwards compatibility', () {
      final columns = ['title', 'views'];
      final rows = <List<Object?>>[
        ['First Post', 42],
        ['Second Post', 100],
      ];

      final dataset = CompactResultDataset.fromRawRows(columns, rows);
      final result = SqlExecutionResult.fromDataset(
        dataset: dataset,
        affectedRows: null,
        statusMessage: '2 rows fetched',
        isTruncated: false,
      );

      expect(result.dataset, same(dataset));
      expect(result.columns, ['title', 'views']);
      expect(result.statusMessage, '2 rows fetched');
      expect(result.isTruncated, isFalse);

      // rows is lazy and fully matches List<List<String>> contract
      expect(result.rows.length, 2);
      expect(result.rows[0], ['First Post', '42']);
      expect(result.rows[1], ['Second Post', '100']);
      expect(result.rows[0][0], 'First Post');
      expect(result.rows[1][1], '100');
    });
  });
}

