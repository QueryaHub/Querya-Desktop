import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
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
  group('VirtualResultGrid Keyboard Navigation & Selection', () {
    testWidgets('navigates cells with arrow keys', (tester) async {
      List<String>? selectedValues;
      String? focusedVal;

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
              onCellFocused: (col, val, row) => focusedVal = val,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'Alice' (row 0, col 1)
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(selectedValues, ['Alice']);
      expect(focusedVal, 'Alice');

      // Press ArrowDown -> should move to 'Bob' (row 1, col 1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(selectedValues, ['Bob']);
      expect(focusedVal, 'Bob');

      // Press ArrowRight -> should move to 'User' (row 1, col 2)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      expect(selectedValues, ['User']);
      expect(focusedVal, 'User');

      // Press ArrowUp -> should move to 'Admin' (row 0, col 2)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(selectedValues, ['Admin']);
      expect(focusedVal, 'Admin');

      // Press ArrowLeft -> should move back to 'Alice' (row 0, col 1)
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();

      expect(selectedValues, ['Alice']);
      expect(focusedVal, 'Alice');
    });

    testWidgets('extends rectangular range selection with Shift+Arrow keys', (tester) async {
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

      // Tap on top-left '1' (row 0, col 0)
      await tester.tap(find.text('1'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(selectedValues, ['1']);

      // Shift + ArrowDown -> extends selection to rows 0..1, col 0
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(selectedValues, ['1', '2']);

      // Shift + ArrowRight -> extends selection to 2x2 box: (row 0..1, col 0..1)
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      expect(selectedValues, ['1', 'Alice', '2', 'Bob']);
    });

    testWidgets('selects all cells with Ctrl+A / Meta+A', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Alice'],
                ['2', 'Bob'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on Alice
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      expect(selectedValues, ['Alice']);

      // Press Ctrl+A
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(selectedValues, ['1', 'Alice', '2', 'Bob']);
    });

    testWidgets('jumps to start and end with Home / End and Ctrl+Home / Ctrl+End', (tester) async {
      List<String>? selectedValues;

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['c1', 'c2', 'c3'],
              rows: const [
                ['r0c0', 'r0c1', 'r0c2'],
                ['r1c0', 'r1c1', 'r1c2'],
                ['r2c0', 'r2c1', 'r2c2'],
              ],
              onSelectionValuesChanged: (vals) => selectedValues = vals,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on middle cell 'r1c1'
      await tester.tap(find.text('r1c1'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(selectedValues, ['r1c1']);

      // Press Home -> moves to 'r1c0'
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.pumpAndSettle();
      expect(selectedValues, ['r1c0']);

      // Press End -> moves to 'r1c2'
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(selectedValues, ['r1c2']);

      // Press Ctrl+Home -> moves to top-left 'r0c0'
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selectedValues, ['r0c0']);

      // Press Ctrl+End -> moves to bottom-right 'r2c2'
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(selectedValues, ['r2c2']);
    });

    testWidgets('presses F2 to start editing on selected cell', (tester) async {
      final staging = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Alice'],
        ],
      );

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Alice'],
              ],
              stagingBuffer: staging,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap once to select Alice
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Press F2 -> opens inline editor
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await tester.pumpAndSettle();

      expect(find.byType(material.TextField), findsOneWidget);
    });
  });
}
