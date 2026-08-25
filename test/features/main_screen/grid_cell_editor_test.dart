import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/main_screen/grid_cell_editor.dart';
import 'package:querya_desktop/features/main_screen/grid_cell_popover_inspector.dart';
import 'package:querya_desktop/features/main_screen/result_grid_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('GridCellEditor', () {
    testWidgets('renders with initial value and commits text on Enter', (tester) async {
      String? committed;
      bool movedRow = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: 'Original',
              width: 200,
              height: 36,
              onCommit: (val, {moveNextCol = false, movePrevCol = false, moveNextRow = false, movePrevRow = false}) {
                committed = val;
                movedRow = moveNextRow;
              },
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Original'), findsOneWidget);

      // Enter new text and submit
      await tester.enterText(find.byType(material.TextField), 'Modified');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(committed, 'Modified');
      expect(movedRow, isTrue);
    });

    testWidgets('triggers onCancel when Escape key is pressed', (tester) async {
      bool cancelled = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: 'Original',
              width: 200,
              height: 36,
              onCommit: (val, {moveNextCol = false, movePrevCol = false, moveNextRow = false, movePrevRow = false}) {},
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(cancelled, isTrue);
    });

    testWidgets('displays validation error icon on invalid integer input', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: '123',
              dataTypeName: 'integer',
              width: 200,
              height: 36,
              onCommit: (val, {moveNextCol = false, movePrevCol = false, moveNextRow = false, movePrevRow = false}) {},
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.error_outline_rounded), findsNothing);

      // Enter non-integer text
      await tester.enterText(find.byType(material.TextField), 'not_a_number');
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.error_outline_rounded), findsOneWidget);
    });
  });

  group('GridCellPopoverInspector', () {
    testWidgets('allows editing and formatting JSON in dialog', (tester) async {
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'metadata',
                  initialValue: '{"name":"querya","active":true}',
                  rowIndex: 0,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Edit metadata (Row 1)'), findsOneWidget);
      expect(find.text('Format JSON'), findsOneWidget);

      // Format JSON
      await tester.tap(find.text('Format JSON'));
      await tester.pumpAndSettle();

      // Apply changes
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.contains('\n'), isTrue);
      expect(result!.contains('"name": "querya"'), isTrue);
    });

    testWidgets('allows setting value to NULL in dialog', (tester) async {
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'age',
                  initialValue: '25',
                  rowIndex: 1,
                );
              },
              child: const Text('Open Dialog'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Set NULL'));
      await tester.pumpAndSettle();

      expect(find.text('Value is NULL'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, 'NULL');
    });
  });

  group('VirtualResultGrid Inline Editing Integration', () {
    testWidgets('double click on cell activates editor and commits staged edit', (tester) async {
      final staging = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Alice'],
          ['2', 'Bob'],
        ],
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Alice'],
                ['2', 'Bob'],
              ],
              stagingBuffer: staging,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(staging.isDirty, isFalse);

      // Double-click on 'Alice'
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Alice'));
      await tester.pumpAndSettle();

      // TextField should now be present for editing
      expect(find.byType(material.TextField), findsOneWidget);

      // Type 'Alice Cooper' and press Done/Enter
      await tester.enterText(find.byType(material.TextField), 'Alice Cooper');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(staging.isDirty, isTrue);
      expect(staging.getCellValue(0, 1), 'Alice Cooper');
    });
  });
}
