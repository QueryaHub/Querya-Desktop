import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/result_grid_view.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('computeResultGridColumnWidths', () {
    test('returns empty list for no columns', () {
      expect(
        computeResultGridColumnWidths(columns: const [], rows: const []),
        isEmpty,
      );
    });

    test('respects min and max width bounds', () {
      final widths = computeResultGridColumnWidths(
        columns: const ['id', 'note'],
        rows: [
          ['1', 'x'],
          ['2', 'y'],
        ],
        minWidth: 100,
        maxWidth: 150,
      );
      expect(widths, hasLength(2));
      for (final w in widths) {
        expect(w, inInclusiveRange(100, 150));
      }
    });

    test('widens columns for long sampled values', () {
      final short = computeResultGridColumnWidths(
        columns: const ['payload'],
        rows: [
          ['a'],
        ],
      ).single;
      final long = computeResultGridColumnWidths(
        columns: const ['payload'],
        rows: [
          ['${'x' * 80}'],
        ],
      ).single;
      expect(long, greaterThan(short));
    });
  });

  group('ResultsTab', () {
    testWidgets('uses virtualized grid instead of Table', (tester) async {
      final rows = List.generate(
        120,
        (i) => ['$i', 'value-$i'],
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: ResultsTab(
              columns: const ['id', 'name'],
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(material.ListView), findsOneWidget);
      expect(find.byType(material.Table), findsNothing);
      expect(find.byType(VirtualResultGrid), findsOneWidget);
    });

    testWidgets('virtualizes rows — does not build all row widgets at once',
        (tester) async {
      final rows = List.generate(
        500,
        (i) => ['$i', 'value-$i'],
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.SizedBox(
            height: 400,
            width: 600,
            child: VirtualResultGrid(
              columns: const ['id', 'name'],
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Header + only visible rows (not all 500).
      final dataRowWidgets = tester.widgetList(find.byType(material.Row)).length;
      expect(dataRowWidgets, lessThan(80));
    });
  });
}
