import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';

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

    testWidgets('debounces rapid keystrokes and notifies only once after debounce duration', (tester) async {
      final changeNotifications = <String>[];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridFilterBar(
              filterText: '',
              onFilterChanged: (text) => changeNotifications.add(text),
              totalRowCount: 100,
              filteredRowCount: 20,
              columns: const ['id', 'name', 'status'],
              debounceDuration: const Duration(milliseconds: 150),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Type first letter 'a'
      await tester.enterText(find.byType(material.TextField), 'a');
      await tester.pump(const Duration(milliseconds: 50));
      // No notification yet
      expect(changeNotifications, isEmpty);

      // Type second letter 'ab' before timer expires
      await tester.enterText(find.byType(material.TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 50));
      expect(changeNotifications, isEmpty);

      // Type third letter 'abc'
      await tester.enterText(find.byType(material.TextField), 'abc');
      await tester.pump(const Duration(milliseconds: 50));
      expect(changeNotifications, isEmpty);

      // Wait remaining debounce duration (100ms more => 150ms since last keystroke)
      await tester.pump(const Duration(milliseconds: 100));
      expect(changeNotifications, ['abc']);
    });

    testWidgets('notifies immediately on submit without waiting for debounce duration', (tester) async {
      final changeNotifications = <String>[];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridFilterBar(
              filterText: '',
              onFilterChanged: (text) => changeNotifications.add(text),
              totalRowCount: 100,
              filteredRowCount: 20,
              columns: const ['id', 'name', 'status'],
              debounceDuration: const Duration(milliseconds: 150),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(material.TextField), 'active');
      // Submit immediately
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(changeNotifications, ['active']);
    });

    testWidgets('cancels pending timer and notifies empty on clear button tap', (tester) async {
      final changeNotifications = <String>[];

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Material(
            child: DataGridFilterBar(
              filterText: 'prefilled',
              onFilterChanged: (text) => changeNotifications.add(text),
              totalRowCount: 100,
              filteredRowCount: 10,
              columns: const ['id', 'name', 'status'],
              debounceDuration: const Duration(milliseconds: 150),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(material.Icons.close));
      await tester.pumpAndSettle();

      expect(changeNotifications, ['']);
    });
  });
}
