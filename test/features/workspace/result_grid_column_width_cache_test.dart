import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
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
  group('VirtualResultGrid column-width distribution cache (#982)', () {
    testWidgets(
        'an unrelated setState (same width, same columns/rows) does not resample column widths again',
        (tester) async {
      await tester.pumpWidget(
        _testShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'name', 'role'],
              rows: [
                ['1', 'Alice', 'Admin'],
                ['2', 'Bob', 'User'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(VirtualResultGrid));
      final firstCount = state.columnWidthDistributionCount as int;
      expect(firstCount, greaterThanOrEqualTo(1));

      // Force a rebuild of the grid's own State without touching its widget
      // (rows/columns/width all unchanged) — the same shape of rebuild a
      // selection change or any other internal setState would cause. The
      // O(columns x rows) sampling must not rerun for it.
      state.setState(() {});
      await tester.pumpAndSettle();

      expect(state.columnWidthDistributionCount, firstCount);
    });

    testWidgets('resizing the viewport does resample column widths',
        (tester) async {
      final key = material.GlobalKey();

      material.Widget build(double width) => _testShell(
            child: material.SizedBox(
              key: key,
              width: width,
              height: 400,
              child: const VirtualResultGrid(
                columns: ['id', 'name', 'role'],
                rows: [
                  ['1', 'Alice', 'Admin'],
                  ['2', 'Bob', 'User'],
                ],
              ),
            ),
          );

      await tester.pumpWidget(build(800));
      await tester.pumpAndSettle();

      final dynamic state = tester.state(find.byType(VirtualResultGrid));
      final firstCount = state.columnWidthDistributionCount as int;

      await tester.pumpWidget(build(500));
      await tester.pumpAndSettle();

      expect(state.columnWidthDistributionCount, greaterThan(firstCount));
    });
  });
}
