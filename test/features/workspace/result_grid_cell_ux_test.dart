import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
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
}
