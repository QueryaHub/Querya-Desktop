import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/data_grid_filter_bar.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  group('FilterSuggestionEngine', () {
    final columns = ['id', 'status', 'amount', 'created_at'];

    test('returns column suggestions when text is empty', () {
      final suggs = FilterSuggestionEngine.getSuggestions(
        text: '',
        columns: columns,
      );
      expect(suggs.length, 4);
      expect(suggs.map((s) => s.text), containsAll(['id', 'status', 'amount', 'created_at']));
    });

    test('suggests matching columns on partial prefix', () {
      final suggs = FilterSuggestionEngine.getSuggestions(
        text: 'sta',
        columns: columns,
      );
      expect(suggs.length, 1);
      expect(suggs.first.text, 'status');
      expect(suggs.first.kind, FilterSuggestionKind.column);
    });

    test('suggests operators after full column name', () {
      final suggs = FilterSuggestionEngine.getSuggestions(
        text: 'status',
        columns: columns,
      );
      expect(suggs.map((s) => s.text), containsAll(['=', '!=', 'LIKE', 'ILIKE', 'IN (...)', 'IS NULL']));
    });

    test('suggests keywords on partial keyword prefix', () {
      final suggs = FilterSuggestionEngine.getSuggestions(
        text: 'status = ACTIVE AN',
        columns: columns,
      );
      expect(suggs.any((s) => s.text == 'AND'), isTrue);
    });
  });

  group('DataGridFilterBar Widget', () {
    testWidgets('renders filter bar and updates text on input', (tester) async {
      String currentFilter = '';

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridFilterBar(
              filterText: currentFilter,
              onFilterChanged: (text) => currentFilter = text,
              totalRowCount: 100,
              filteredRowCount: 20,
              columns: const ['id', 'name', 'status'],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(material.TextField), findsOneWidget);

      await tester.enterText(find.byType(material.TextField), 'stat');
      await tester.pumpAndSettle();

      expect(currentFilter, 'stat');
      expect(find.text('status'), findsOneWidget);
    });
  });
}
