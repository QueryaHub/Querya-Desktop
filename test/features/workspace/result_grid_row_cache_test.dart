import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

material.Widget _testShell({required material.Widget child}) {
  return queryaThemeTestShell(
    child: material.Scaffold(
      body: child,
    ),
  );
}

void main() {
  group('VirtualResultGrid row memo cache eviction (#1010)', () {
    testWidgets(
        'caches built rows and clears cache when stagingBuffer is swapped',
        (tester) async {
      final buffer1 = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: List.generate(20, (i) => ['$i', 'Item $i']),
      );
      final buffer2 = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: List.generate(10, (i) => ['new_$i', 'New $i']),
      );

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: buffer1.effectiveRows,
              stagingBuffer: buffer1,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(VirtualResultGrid));
      expect(state.rowWidgetsCacheCount, greaterThan(0));

      // Swap to buffer2
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: buffer2.effectiveRows,
              stagingBuffer: buffer2,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state.rowWidgetsCacheCount, greaterThan(0));
      expect(state.rowWidgetsCacheCount, lessThanOrEqualTo(10));
    });

    testWidgets('clears cache when columns change', (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'name'],
              rows: [
                ['1', 'Alpha'],
                ['2', 'Beta'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(VirtualResultGrid));
      expect(state.rowWidgetsCacheCount, 2);

      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['col_a', 'col_b', 'col_c'],
              rows: [
                ['1', 'Alpha', 'Extra'],
                ['2', 'Beta', 'Extra'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(state.rowWidgetsCacheCount, 2);
    });

    testWidgets(
        'bounds cache size and evicts far rows during heavy vertical scroll',
        (tester) async {
      final rows = List.generate(350, (i) => ['$i', 'Value $i']);
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'value'],
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(VirtualResultGrid));
      expect(state.rowWidgetsCacheCount, lessThan(100));

      // Scroll down across hundreds of rows
      for (int i = 0; i < 15; i++) {
        await tester.drag(
          find.byType(VirtualResultGrid),
          const material.Offset(0, -600),
        );
        await tester.pump();
      }
      await tester.pumpAndSettle();

      // Even after scrolling through 350 rows, the cache must remain bounded (<= 200)
      expect(state.rowWidgetsCacheCount, lessThanOrEqualTo(200));
    });
  });
}
