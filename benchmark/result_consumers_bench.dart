// What the consumers of a big result set cost through the dataset's lazy row
// list versus a `List<List<String>>` built from it (#1549). Headless:
//   flutter test benchmark/result_consumers_bench.dart --dart-define=ROWS=50000
// Prints `RESULT <consumer> materialized=<ms> lazy=<ms>` (median of 5, after a
// warm-up). Memory is not measured here: RSS in the test runner is too noisy.
// The 50k x 20 figures in #1549 (68.6 MiB as strings, 17.5 MiB columnar) came
// from a standalone AOT run.
//
// Decision (see #1549): consumers keep `List<List<String>>` at their boundary.
// At 50k x 20 the lazy list is as fast for sort and filter on typed columns,
// and 25-40 ms slower for a free-text filter and the CSV export, which run
// once per user action; the app only ever holds the columnar dataset.
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/compact_result_dataset.dart';
import 'package:querya_desktop/features/workspace/grid/grid_sorting.dart';
import 'package:querya_desktop/features/workspace/grid_filter_engine.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

const _rows = int.fromEnvironment('ROWS', defaultValue: 50000);

List<List<Object?>> _source(int n) => [
      for (var i = 0; i < n; i++)
        [
          for (var c = 0; c < 20; c++)
            c < 6
                ? i * 7 % 10007 + c
                : c < 10
                    ? i * 0.37 + c
                    : 'v${(i * 31) % 5000}_$c',
        ],
    ];

void main() {
  test('result set consumers: lazy dataset rows vs materialized strings', () {
    final names = [for (var c = 0; c < 20; c++) 'c$c'];

    final dataset = CompactResultDataset.fromRawRows(names, _source(_rows));
    final materialized = [for (var i = 0; i < _rows; i++) dataset.rowStrings(i)];
    final lazy = dataset.asLazyRowList();
    int time(void Function() f) {
      final sw = Stopwatch()..start();
      f();
      return sw.elapsedMilliseconds;
    }

    void consumer(String name, void Function(List<List<String>>) run) {
      run(materialized);
      run(lazy);
      final m = [for (var i = 0; i < 5; i++) time(() => run(materialized))]
        ..sort();
      final l = [for (var i = 0; i < 5; i++) time(() => run(lazy))]..sort();
      // ignore: avoid_print
      print('RESULT $name materialized=${m[2]}ms lazy=${l[2]}ms');
    }

    consumer(
        'sort int column',
        (r) => sortResultGridRowsWithIndices(
            rows: r, columnIndex: 0, order: ResultGridSortOrder.ascending));
    consumer(
        'sort double column',
        (r) => sortResultGridRowsWithIndices(
            rows: r, columnIndex: 7, order: ResultGridSortOrder.ascending));
    consumer(
        'sort string column',
        (r) => sortResultGridRowsWithIndices(
            rows: r, columnIndex: 12, order: ResultGridSortOrder.descending));
    consumer(
        'filter c0 > 5000',
        (r) => GridFilterEngine.filterRowIndices(
            filterText: 'c0 > 5000', columns: names, rows: r));
    consumer(
        'filter free text',
        (r) => GridFilterEngine.filterRowIndices(
            filterText: 'v42', columns: names, rows: r));
    consumer('csv export', (r) => DataExportService.formatCsv(names, r));
  });
}
