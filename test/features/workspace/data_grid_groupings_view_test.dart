import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_groupings_view.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('DataGridGroupingsView Widget', () {
    final columns = ['category', 'amount'];
    final rows = [
      ['Electronics', '100'],
      ['Electronics', '200'],
      ['Books', '50'],
    ];

    testWidgets('renders empty state when columns or rows are empty', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: const material.Material(
            child: DataGridGroupingsView(
              columns: [],
              rows: [],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No data available for grouping.'), findsOneWidget);
    });

    testWidgets('renders grouping categories and allows aggregation switching', (tester) async {
      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridGroupingsView(
              columns: columns,
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Groups should be displayed
      expect(find.text('Electronics'), findsOneWidget);
      expect(find.text('Books'), findsOneWidget);
      expect(find.text('2 rows (66.7%)'), findsOneWidget);
      expect(find.text('1 rows (33.3%)'), findsOneWidget);

      // Expand a group
      await tester.tap(find.text('Electronics'));
      await tester.pumpAndSettle();

      // Copy Pivot CSV button
      expect(find.byTooltip('Copy Pivot CSV to Clipboard'), findsOneWidget);
      await tester.tap(find.byTooltip('Copy Pivot CSV to Clipboard'));
      await tester.pumpAndSettle();
    });
  });
}
