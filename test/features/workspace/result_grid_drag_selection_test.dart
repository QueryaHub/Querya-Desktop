import 'package:flutter/gestures.dart';
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
  group('VirtualResultGrid Mouse Drag Range Selection', () {
    testWidgets('selects rectangular range of cells via mouse drag', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name', 'role'],
              rows: const [
                ['1', 'Alice', 'Admin'],
                ['2', 'Bob', 'User'],
                ['3', 'Charlie', 'Manager'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start drag from cell '1' (row 0, col 0) to 'Bob' (row 1, col 1)
      final startPos = tester.getCenter(find.text('1'));
      final endPos = tester.getCenter(find.text('Bob'));

      final gesture = await tester.startGesture(startPos, kind: PointerDeviceKind.mouse);
      await tester.pump();

      await gesture.moveTo(endPos);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      // Should select 2x2 box: (row 0..1, col 0..1) -> ['1', 'Alice', '2', 'Bob']
      expect(selectedValues, ['1', 'Alice', '2', 'Bob']);
    });

    testWidgets('supports reverse drag selection (bottom-right to top-left)', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name', 'role'],
              rows: const [
                ['1', 'Alice', 'Admin'],
                ['2', 'Bob', 'User'],
                ['3', 'Charlie', 'Manager'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Start drag from 'Manager' (row 2, col 2) up-left to 'Alice' (row 0, col 1)
      final startPos = tester.getCenter(find.text('Manager'));
      final endPos = tester.getCenter(find.text('Alice'));

      final gesture = await tester.startGesture(startPos, kind: PointerDeviceKind.mouse);
      await tester.pump();

      await gesture.moveTo(endPos);
      await tester.pump();

      await gesture.up();
      await tester.pumpAndSettle();

      // Should select rectangle rows 0..2, cols 1..2
      expect(selectedValues, ['Alice', 'Admin', 'Bob', 'User', 'Charlie', 'Manager']);
    });

    testWidgets('single click without drag selects only one cell', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name', 'role'],
              rows: const [
                ['1', 'Alice', 'Admin'],
                ['2', 'Bob', 'User'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(selectedValues, ['Alice']);
    });

    testWidgets('drag selection auto-scrolls vertically when dragged past viewport edge', (tester) async {
      List<String>? selectedValues;

      // 50 rows in a 200px high grid so vertical scrolling is required
      final rows = List.generate(50, (i) => ['$i', 'Name $i', 'Role $i']);

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 200,
            child: VirtualResultGrid(
              columns: const ['id', 'name', 'role'],
              rows: rows,
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final startPos = tester.getCenter(find.text('Name 0'));
      final gesture = await tester.startGesture(startPos, kind: PointerDeviceKind.mouse);
      await tester.pump();

      // Move downwards past the bottom edge of the grid viewport (e.g. y = 195)
      await gesture.moveTo(material.Offset(startPos.dx, 195));
      await tester.pump();

      // Wait for auto-scroll timer ticks
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      await gesture.up();
      await tester.pumpAndSettle();

      // Selection should span more than the initial visible rows (e.g. from row 0 to at least row 5)
      expect(selectedValues, isNotNull);
      expect(selectedValues!.length, greaterThan(6));
    });
  });
}
