import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/workspace/data_grid_filter_bar.dart';

import '../../support/fake_table_data_delegate.dart';
import '../../support/generic_table_view_harness.dart';

void main() {
  Future<void> openFilter(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Toggle Quick Filter'));
    await tester.pumpAndSettle();
  }

  Future<void> typeFilter(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(DataGridFilterBar),
        matching: find.byType(material.TextField),
      ),
      text,
    );
    // Let the filter bar's debounce fire.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
  }

  group('loading and paging', () {
    testWidgets('shows the loaded page and its range', (tester) async {
      final state = await pumpGenericTableView(tester, FakeTableDataDelegate());

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
      expect(state.paginationLabel(), '1–3 of 3');
      expect(state.rowsOnPage, 3);
    });

    testWidgets('Next and Prev move between pages', (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate, limit: 2);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Carol'), findsNothing);
      expect(state.canGoNext, isTrue);
      expect(state.canGoPrevious, isFalse);

      state.goToNextPage();
      await tester.pumpAndSettle();
      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(state.offset, 2);
      expect(state.canGoNext, isFalse);
      expect(state.paginationLabel(), '3–3 of 3');

      state.goToPreviousPage();
      await tester.pumpAndSettle();
      expect(find.text('Alice'), findsOneWidget);
      expect(state.offset, 0);
      expect(delegate.pagesLoaded.map((p) => p.offset), [0, 2, 0]);
    });

    testWidgets('Refresh reloads the current page and the row count',
        (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate);
      expect(delegate.pagesLoaded, hasLength(1));

      await state.refresh();
      await tester.pumpAndSettle();

      expect(delegate.pagesLoaded, hasLength(2));
      expect(delegate.pagesLoaded.last.refreshCount, isTrue);
    });

    testWidgets('a load failure is shown instead of the grid', (tester) async {
      final state = await pumpGenericTableView(
        tester,
        FakeTableDataDelegate(failLoadWith: StateError('connection lost')),
      );

      expect(state.error, contains('connection lost'));
      expect(find.textContaining('connection lost'), findsWidgets);
      expect(find.text('Alice'), findsNothing);
    });

    testWidgets('custom SQL replaces the browse view and Browse returns',
        (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate);

      await state.runCustomSql('SELECT 42 AS n');
      await tester.pumpAndSettle();
      expect(state.customSqlActive, isTrue);
      expect(delegate.customQueries, ['SELECT 42 AS n']);
      expect(find.text('42'), findsOneWidget);
      expect(state.canEdit, isFalse);

      await state.exitCustomMode();
      await tester.pumpAndSettle();
      expect(state.customSqlActive, isFalse);
      expect(find.text('Alice'), findsOneWidget);
    });

    testWidgets('only SELECT statements are accepted as custom SQL',
        (tester) async {
      final delegate = FakeTableDataDelegate();
      final state = await pumpGenericTableView(tester, delegate);

      await state.runCustomSql('DELETE FROM users');
      await tester.pumpAndSettle();

      expect(state.customSqlActive, isFalse);
      expect(delegate.customQueries, isEmpty);
    });
  });

  group('quick filter', () {
    testWidgets('filters the rows on the page and shows the match count',
        (tester) async {
      await pumpGenericTableView(tester, FakeTableDataDelegate());
      await openFilter(tester);

      await typeFilter(tester, 'bob');

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Carol'), findsNothing);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('column = value predicates are understood', (tester) async {
      await pumpGenericTableView(tester, FakeTableDataDelegate());
      await openFilter(tester);

      await typeFilter(tester, 'name = Carol');

      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.text('Bob'), findsNothing);
    });

    testWidgets('clearing the filter brings every row back', (tester) async {
      await pumpGenericTableView(tester, FakeTableDataDelegate());
      await openFilter(tester);
      await typeFilter(tester, 'bob');
      expect(find.text('Alice'), findsNothing);

      await typeFilter(tester, '');

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Carol'), findsOneWidget);
    });
  });

  group('calc bar', () {
    testWidgets('shows aggregates for the selected cell', (tester) async {
      await pumpGenericTableView(tester, FakeTableDataDelegate());

      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();

      expect(find.text('Count: '), findsOneWidget);
    });
  });
}
