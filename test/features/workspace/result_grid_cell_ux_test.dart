import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/grid_cell_editor.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('ResultGridMetrics.cellTooltipMessage', () {
    test('null when the value is short and no type is known', () {
      expect(
        ResultGridMetrics.cellTooltipMessage(text: 'Ada'),
        isNull,
      );
    });

    test('shows column · type when schema metadata is present', () {
      expect(
        ResultGridMetrics.cellTooltipMessage(
          text: 'Ada',
          columnName: 'name',
          dataTypeName: 'text',
        ),
        'name · text',
      );
    });

    test('shows type only when the column name is empty', () {
      expect(
        ResultGridMetrics.cellTooltipMessage(
          text: '1',
          dataTypeName: 'integer',
        ),
        'integer',
      );
    });

    test('appends long cell values under the type line', () {
      final long = 'x' * ResultGridMetrics.tooltipMinLength;
      expect(
        ResultGridMetrics.cellTooltipMessage(
          text: long,
          columnName: 'bio',
          dataTypeName: 'text',
        ),
        'bio · text\n$long',
      );
    });

    test('falls back to the long value when no type is known', () {
      final long = 'y' * ResultGridMetrics.tooltipMinLength;
      expect(
        ResultGridMetrics.cellTooltipMessage(text: long),
        long,
      );
    });
  });

  group('VirtualResultGrid cell hover', () {
    testWidgets('editable cells use the text cursor', (tester) async {
      final staging = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: const [
          ['1', 'Ada'],
        ],
      );
      addTearDown(staging.dispose);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Ada'],
              ],
              stagingBuffer: staging,
              columnDataTypes: const {'id': 'integer', 'name': 'text'},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textCursors = tester
          .widgetList<material.MouseRegion>(find.byType(material.MouseRegion))
          .where((r) => r.cursor == material.SystemMouseCursors.text);
      expect(textCursors, isNotEmpty);
    });

    testWidgets('read-only cells do not use the text cursor', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: ['id', 'name'],
              rows: [
                ['1', 'Ada'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final textCursors = tester
          .widgetList<material.MouseRegion>(find.byType(material.MouseRegion))
          .where((r) => r.cursor == material.SystemMouseCursors.text);
      expect(textCursors, isEmpty);
    });
  });

  group('VirtualResultGrid cell editor', () {
    testWidgets(
        'clicking inside the open editor does not discard the in-progress edit (#1006)',
        (tester) async {
      final staging = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: const [
          ['1', 'Ada'],
        ],
      );
      addTearDown(staging.dispose);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Ada'],
              ],
              stagingBuffer: staging,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cellCenter = tester.getCenter(find.text('Ada'));
      await tester.tapAt(cellCenter, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(cellCenter, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();

      expect(find.byType(GridCellEditor), findsOneWidget,
          reason: 'double-click should open the inline editor');

      await tester.enterText(find.byType(material.TextField), 'Alicia');
      await tester.pump();

      // Click inside the open editor — e.g. to reposition the caret — must
      // not close it or discard the value typed so far.
      await tester.tapAt(
        tester.getCenter(find.byType(GridCellEditor)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridCellEditor), findsOneWidget,
          reason: 'a click inside the editor must not cancel the edit');
      expect(find.text('Alicia'), findsOneWidget,
          reason: 'the typed value must survive a click inside the editor');
    });

    testWidgets('clicking a different cell while editing cancels the edit',
        (tester) async {
      final staging = DataGridStagingBuffer(
        columns: const ['id', 'name'],
        rows: const [
          ['1', 'Ada'],
          ['2', 'Bob'],
        ],
      );
      addTearDown(staging.dispose);

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.SizedBox(
            width: 800,
            height: 400,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: const [
                ['1', 'Ada'],
                ['2', 'Bob'],
              ],
              stagingBuffer: staging,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final cellCenter = tester.getCenter(find.text('Ada'));
      await tester.tapAt(cellCenter, kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(cellCenter, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(find.byType(GridCellEditor), findsOneWidget);

      await tester.tapAt(
        tester.getCenter(find.text('Bob')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();

      expect(find.byType(GridCellEditor), findsNothing);
    });
  });
}
