import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/grid/grid_sorting.dart';

/// #1533: date keys are read without DateTime.parse's local constructor per
/// row, with the same instants and therefore the same order.
void main() {
  int? reference(String s) => DateTime.tryParse(s)?.microsecondsSinceEpoch;
  int? fast(String s, Map<int, int> cache) =>
      isoMicrosSinceEpoch(s, localOffsets: cache) ?? reference(s);

  const shapes = [
    '2026-01-02',
    '2026-01-02T03:04',
    '2026-01-02T03:04:05',
    '2026-01-02 03:04:05.123',
    '2026-01-02T03:04:05.1234567',
    '2026-01-02T03:04:05Z',
    '2026-01-02t03:04:05z',
    '2026-01-02T03:04:05.5+03:00',
    '2026-01-02T03:04:05-0530',
    '2026-01-02T03:04:05+02',
    '2026-02-30 12:00',
    '2026-01-02T25:61:61',
    // Daylight-saving changes in Europe and the US, and the hours around them.
    '2026-03-29T01:59:59', '2026-03-29T02:30', '2026-03-29T03:00',
    '2026-10-25T01:30', '2026-10-25T02:30', '2026-10-25T03:00',
    '2026-03-08T02:30', '2026-11-01T01:30',
    // Shapes left to DateTime.tryParse.
    '20260102', '2026-01-02T10', '2026-01-02 Z', '+2026-01-02', 'x', '',
  ];

  test('the same instant as DateTime.parse for every shape', () {
    final cache = <int, int>{};
    for (final s in shapes) {
      expect(fast(s, cache), reference(s), reason: s);
    }
    // A second pass reads the cached offsets.
    for (final s in shapes) {
      expect(fast(s, cache), reference(s), reason: 'cached: $s');
    }
  });

  test('shapes it does not read are left to DateTime.tryParse', () {
    for (final s in ['20260102', '2026-01-02T10', '2026-01-02 Z', 'x', '']) {
      expect(isoMicrosSinceEpoch(s), isNull, reason: s);
    }
  });

  test('a timestamp column sorts by time, NULL and empty last', () {
    final rows = [
      ['2026-01-02T10:00:00'],
      ['NULL'],
      ['2025-12-31 23:59:59.999'],
      [''],
      ['2026-01-02T09:00:00Z'],
      ['2026-01-01'],
    ];
    final asc = sortResultGridRowsWithIndices(
      rows: rows,
      columnIndex: 0,
      order: ResultGridSortOrder.ascending,
    );
    final instants = [
      for (final i in asc.sortedToModelIndices.take(4))
        DateTime.parse(rows[i][0]).microsecondsSinceEpoch,
    ];
    expect(instants, [...instants]..sort());
    expect(asc.sortedToModelIndices.skip(4).toSet(), {1, 3});
  });
}
