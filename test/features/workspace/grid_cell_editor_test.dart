import 'package:flutter/widgets.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/grid_cell_editor.dart';
import 'package:querya_desktop/features/workspace/grid_cell_popover_inspector.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:querya_desktop/shared/widgets/querya_spinner.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('GridCellEditor', () {
    testWidgets('renders with initial value and commits text on Enter',
        (tester) async {
      String? committed;
      bool movedRow = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: 'Original',
              width: 200,
              height: 36,
              onCommit: (val,
                  {moveNextCol = false,
                  movePrevCol = false,
                  moveNextRow = false,
                  movePrevRow = false}) {
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

    testWidgets('invokes onCommit exactly once on Enter key press without double commit',
        (tester) async {
      int commitCount = 0;
      String? committed;
      bool movedRow = false;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: 'Hello',
              width: 200,
              height: 36,
              onCommit: (val,
                  {moveNextCol = false,
                  movePrevCol = false,
                  moveNextRow = false,
                  movePrevRow = false}) {
                commitCount++;
                committed = val;
                movedRow = moveNextRow;
              },
              onCancel: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(commitCount, 1);
      expect(committed, 'Hello');
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
              onCommit: (val,
                  {moveNextCol = false,
                  movePrevCol = false,
                  moveNextRow = false,
                  movePrevRow = false}) {},
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

    testWidgets('displays validation error icon on invalid integer input',
        (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: GridCellEditor(
              initialValue: '123',
              dataTypeName: 'integer',
              width: 200,
              height: 36,
              onCommit: (val,
                  {moveNextCol = false,
                  movePrevCol = false,
                  moveNextRow = false,
                  movePrevRow = false}) {},
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
      final errorIcon = tester.widget<material.Icon>(
        find.byIcon(material.Icons.error_outline_rounded),
      );
      expect(
        errorIcon.color,
        QueryaTheme.darkDefault.colors.destructive,
      );
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

    group('text past the isolate threshold', () {
      final saved = inspectorIsolateThreshold;
      setUp(() => inspectorIsolateThreshold = 64);
      tearDown(() => inspectorIsolateThreshold = saved);

      // `compute` runs on a real isolate, which the fake-async test zone does
      // not wait for: give it real time between pumps.
      Future<void> waitUntil(
        WidgetTester tester,
        bool Function() done,
      ) async {
        for (var i = 0; i < 100 && !done(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 50)),
          );
          await tester.pump();
        }
      }

      testWidgets('JSON is detected and formatted off the UI thread',
          (tester) async {
        final big =
            '[${List.generate(12, (i) => '{"id":$i,"v":"xxxxxxxxxx"}').join(',')}]';
        expect(big.length, greaterThan(inspectorIsolateThreshold));
        String? result;

        await tester.pumpWidget(
          queryaThemeTestShell(
            child: material.Builder(
              builder: (context) => material.ElevatedButton(
                onPressed: () async {
                  result = await showGridCellInspectorDialog(
                    context: context,
                    columnName: 'metadata',
                    initialValue: big,
                    rowIndex: 0,
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();

        // The check runs on the worker; the button shows when it answers.
        await waitUntil(tester, () => find.text('Format JSON').evaluate().isNotEmpty);
        expect(find.text('Format JSON'), findsOneWidget);

        await tester.tap(find.text('Format JSON'));
        await tester.pump();
        await waitUntil(tester, () => find.byType(QueryaSpinner).evaluate().isEmpty);

        await tester.tap(find.text('Apply'));
        await tester.pumpAndSettle();
        expect(result, isNotNull);
        expect(result!.contains('\n'), isTrue);
        expect(result!.contains('"id": 11'), isTrue);
      });

      testWidgets('plain large text does not get JSON buttons', (tester) async {
        await tester.pumpWidget(
          queryaThemeTestShell(
            child: material.Builder(
              builder: (context) => material.ElevatedButton(
                onPressed: () => showGridCellInspectorDialog(
                  context: context,
                  columnName: 'notes',
                  initialValue: 'x' * 200,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open Dialog'));
        await tester.pumpAndSettle();
        expect(find.text('Format JSON'), findsNothing);
        expect(find.text('Format XML'), findsNothing);
      });
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

    testWidgets('formats XML content in dialog', (tester) async {
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'payload',
                  initialValue: '<root><item id="1">data</item></root>',
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

      expect(find.text('Format XML'), findsOneWidget);

      await tester.tap(find.text('Format XML'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.contains('\n'), isTrue);
      expect(result!.contains('  <item'), isTrue);
    });

    testWidgets('formats Hex BLOB content in dialog', (tester) async {
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'bin_data',
                  initialValue: r'\xdeadbeef1234',
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

      expect(find.text('Format Hex'), findsOneWidget);

      await tester.tap(find.text('Format Hex'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, r'\x DE AD BE EF 12 34');
    });

    testWidgets('toggles wrap and applies with Ctrl+Enter shortcut',
        (tester) async {
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'notes',
                  initialValue: 'Hello world',
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

      // Toggle wrap
      expect(find.text('Wrap'), findsOneWidget);
      await tester.tap(find.text('Wrap'));
      await tester.pumpAndSettle();
      expect(find.text('No Wrap'), findsOneWidget);

      // Verify metrics info text rendered
      expect(find.textContaining('1 line · 11 chars'), findsOneWidget);

      // Send Ctrl+Enter to apply
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(result, 'Hello world');
    });

    testWidgets('Save to DB writes through the callback and closes',
        (tester) async {
      String? saved;
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'name',
                  initialValue: 'Ada',
                  onSaveToDatabase: (value) async {
                    saved = value;
                  },
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

      expect(find.text('Save to DB'), findsOneWidget);
      await tester.tap(find.text('Save to DB'));
      await tester.pumpAndSettle();

      expect(saved, 'Ada');
      expect(result, 'Ada');
      expect(find.text('Save to DB'), findsNothing);
    });

    testWidgets('Apply persists through onSaveToDatabase after edit',
        (tester) async {
      String? saved;
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'name',
                  initialValue: 'Ada',
                  onSaveToDatabase: (value) async {
                    saved = value;
                  },
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

      await tester.enterText(find.byType(material.TextField), 'Bob');
      await tester.pumpAndSettle();

      expect(find.text('Apply'), findsOneWidget);
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(saved, 'Bob');
      expect(result, 'Bob');
      expect(find.text('Save to DB'), findsNothing);
    });

    testWidgets('Ctrl+Enter persists through onSaveToDatabase', (tester) async {
      String? saved;
      String? result;

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Builder(
            builder: (context) => material.ElevatedButton(
              onPressed: () async {
                result = await showGridCellInspectorDialog(
                  context: context,
                  columnName: 'name',
                  initialValue: 'Ada',
                  onSaveToDatabase: (value) async {
                    saved = value;
                  },
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

      await tester.enterText(find.byType(material.TextField), 'Bob');
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();

      expect(saved, 'Bob');
      expect(result, 'Bob');
    });
  });

  group('VirtualResultGrid Inline Editing Integration', () {
    testWidgets('double click on cell activates editor and commits staged edit',
        (tester) async {
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
