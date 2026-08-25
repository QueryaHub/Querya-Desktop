import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_toolbar.dart';
import 'package:querya_desktop/features/main_screen/result_grid_view.dart';
import 'package:querya_desktop/features/main_screen/results_tab.dart';

import '../../support/querya_theme_test_shell.dart';

void main() {
  material.Widget resultsShell({
    required material.Widget child,
    QueryaMotionLevel level = QueryaMotionLevel.full,
  }) {
    return queryaThemeTestShell(
      child: QueryaMotionScope(
        level: level,
        child: child,
      ),
    );
  }

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
          ['x' * 80],
        ],
      ).single;
      expect(long, greaterThan(short));
    });
  });

  group('sortResultGridRows', () {
    test('sorts numerically when all values are numbers', () {
      final rows = [
        ['10', 'b'],
        ['2', 'a'],
        ['1', 'c'],
      ];
      final sortedAsc = sortResultGridRows(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
      );
      expect(sortedAsc.map((r) => r[0]).toList(), ['1', '2', '10']);

      final sortedDesc = sortResultGridRows(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.descending,
      );
      expect(sortedDesc.map((r) => r[0]).toList(), ['10', '2', '1']);
    });

    test('sorts lexicographically for non-numeric strings', () {
      final rows = [
        ['banana'],
        ['Apple'],
        ['cherry'],
      ];
      final sorted = sortResultGridRows(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
      );
      expect(sorted.map((r) => r[0]).toList(), ['Apple', 'banana', 'cherry']);
    });

    test('handles NULL and empty values gracefully', () {
      final rows = [
        ['100'],
        ['NULL'],
        ['50'],
        [''],
      ];
      final sorted = sortResultGridRows(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
      );
      expect(sorted.map((r) => r[0]).take(2).toList(), ['50', '100']);
    });
  });

  group('ResultGridSelection', () {
    test('contains point inside bounding box', () {
      const selection = ResultGridSelection(
        startRow: 1,
        startColumn: 1,
        endRow: 3,
        endColumn: 4,
      );
      expect(selection.contains(1, 1), isTrue);
      expect(selection.contains(2, 3), isTrue);
      expect(selection.contains(3, 4), isTrue);
      expect(selection.contains(0, 1), isFalse);
      expect(selection.contains(1, 5), isFalse);
    });

    test('toTsv formats tab-delimited grid', () {
      final rows = [
        ['1', 'Alice', 'Engineer'],
        ['2', 'Bob', 'Designer'],
        ['3', 'Charlie', 'Manager'],
      ];
      final selection = ResultGridSelection.fromPoints(
        anchor: const ResultGridCellCoordinate(0, 1),
        focus: const ResultGridCellCoordinate(1, 2),
      );
      final tsv = selection.toTsv(rows);
      expect(tsv, 'Alice\tEngineer\nBob\tDesigner');
    });

    test('toCsv formats comma-separated grid with quotes if needed', () {
      final rows = [
        ['1', 'Alice, Jr.', 'Engineer'],
        ['2', 'Bob', 'Designer'],
      ];
      final selection = ResultGridSelection.fromPoints(
        anchor: const ResultGridCellCoordinate(0, 0),
        focus: const ResultGridCellCoordinate(1, 1),
      );
      final csv = selection.toCsv(rows);
      expect(csv, '1,"Alice, Jr."\n2,Bob');
    });
  });

  group('computeVisibleColumnWindow', () {
    test('returns empty for no columns', () {
      expect(
        computeVisibleColumnWindow(
          columnWidths: const [],
          columnOffsets: const [0],
          scrollOffset: 0,
          viewportWidth: 400,
        ),
        ResultGridColumnWindow.empty,
      );
    });

    test('keeps far columns out of a narrow viewport', () {
      final widths = List<double>.filled(80, 120);
      final offsets = computeResultGridColumnOffsets(widths);
      final window = computeVisibleColumnWindow(
        columnWidths: widths,
        columnOffsets: offsets,
        scrollOffset: 0,
        viewportWidth: 400,
        overscanColumns: 1,
      );
      // ~4 visible + 1 overscan on the right → last around 4.
      expect(window.first, 0);
      expect(window.last, lessThan(10));
      expect(window.columnCount, lessThan(12));
      expect(window.leadingWidth, 0);
      expect(window.trailingWidth, greaterThan(0));
    });

    test('shifts window when scrolled horizontally', () {
      final widths = List<double>.filled(50, 100);
      final offsets = computeResultGridColumnOffsets(widths);
      final window = computeVisibleColumnWindow(
        columnWidths: widths,
        columnOffsets: offsets,
        scrollOffset: 2000,
        viewportWidth: 300,
        overscanColumns: 0,
      );
      expect(window.first, greaterThan(15));
      expect(window.last, lessThan(30));
      expect(window.leadingWidth, greaterThan(0));
    });

    test('handles large scale column sets (10000 columns) efficiently', () {
      final widths = List<double>.filled(10000, 100);
      final offsets = computeResultGridColumnOffsets(widths);
      final window = computeVisibleColumnWindow(
        columnWidths: widths,
        columnOffsets: offsets,
        scrollOffset: 500000,
        viewportWidth: 1000,
        overscanColumns: 2,
      );
      // scrollOffset 500000 = index 5000 (since width is 100)
      // viewport 1000 = 10 columns (indices 5000..5009)
      // with overscan 2 -> first: 4998, last: 5011
      expect(window.first, 4998);
      expect(window.last, 5011);
      expect(window.leadingWidth, 4998 * 100.0);
    });
  });

  group('ResultsTab', () {
    testWidgets('uses virtualized grid instead of Table', (tester) async {
      final rows = List.generate(
        120,
        (i) => ['$i', 'value-$i'],
      );

      await tester.pumpWidget(
        resultsShell(
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
      expect(find.byType(QueryaFadeSlide), findsOneWidget);
      expect(
        find.byKey(const material.ValueKey('results_mode_grid')),
        findsOneWidget,
      );
    });

    testWidgets('virtualizes rows — does not build all row widgets at once',
        (tester) async {
      final rows = List.generate(
        500,
        (i) => ['$i', 'value-$i'],
      );

      await tester.pumpWidget(
        resultsShell(
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
      final dataRowWidgets =
          tester.widgetList(find.byType(material.Row)).length;
      expect(dataRowWidgets, lessThan(80));
    });

    testWidgets('does not build off-screen columns in a wide grid',
        (tester) async {
      final columns = List.generate(80, (i) => 'col_$i');
      final rows = List.generate(
        40,
        (r) => List.generate(80, (c) => 'r${r}_c$c'),
      );

      await tester.pumpWidget(
        resultsShell(
          child: material.SizedBox(
            height: 400,
            width: 360,
            child: VirtualResultGrid(
              columns: columns,
              rows: rows,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('col_0'), findsOneWidget);
      expect(find.text('col_79'), findsNothing);
      expect(find.text('r0_c0'), findsOneWidget);
      expect(find.text('r0_c79'), findsNothing);

      // Far fewer Text widgets than rows×cols (40×80=3200).
      final texts = tester.widgetList(find.byType(material.Text)).length;
      expect(texts, lessThan(400));
    });

    testWidgets(
        'recalculates column widths when updated with different columns without throwing RangeError',
        (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.SizedBox(
            height: 400,
            width: 600,
            child: VirtualResultGrid(
              columns: ['id', 'name'],
              rows: [
                ['1', 'Alpha'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Now update the grid with 5 columns instead of 2
      await tester.pumpWidget(
        resultsShell(
          child: const material.SizedBox(
            height: 400,
            width: 600,
            child: VirtualResultGrid(
              columns: ['id', 'name', 'email', 'status', 'created_at'],
              rows: [
                ['1', 'Alpha', 'alpha@example.com', 'active', '2026-07-13'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('email'), findsOneWidget);
      expect(find.text('created_at'), findsOneWidget);
    });

    testWidgets('shows error when isLoading is false', (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(
              isLoading: false,
              errorMessage: 'connection refused',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const material.ValueKey('results_mode_error')),
        findsOneWidget,
      );
      expect(find.textContaining('connection refused'), findsOneWidget);
      expect(
        find.byKey(const material.ValueKey('results_mode_loading')),
        findsNothing,
      );
    });

    testWidgets('shows idle / loading / error / grid mode keys', (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Run a query to see results here.'), findsOneWidget);
      expect(
        find.byKey(const material.ValueKey('results_mode_idle')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(isLoading: true),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const material.ValueKey('results_mode_loading')),
        findsOneWidget,
      );
      expect(find.byType(material.CircularProgressIndicator), findsOneWidget);

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(errorMessage: 'syntax error near SELECT'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const material.ValueKey('results_mode_error')),
        findsOneWidget,
      );
      expect(find.textContaining('syntax error'), findsOneWidget);

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(
              columns: ['id'],
              rows: [
                ['1'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const material.ValueKey('results_mode_grid')),
        findsOneWidget,
      );
    });

    testWidgets('morphs idle → loading → grid through FadeSlide', (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const material.ValueKey('results_mode_idle')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(isLoading: true),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(
        find.byKey(const material.ValueKey('results_mode_loading')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(
              columns: ['id', 'name'],
              rows: [
                ['1', 'alpha'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(VirtualResultGrid), findsOneWidget);
      expect(find.text('alpha'), findsOneWidget);
      expect(
        find.byKey(const material.ValueKey('results_mode_idle')),
        findsNothing,
      );
      expect(
        find.byKey(const material.ValueKey('results_mode_loading')),
        findsNothing,
      );
    });

    testWidgets('motion off snaps modes without lingering previous key',
        (tester) async {
      await tester.pumpWidget(
        resultsShell(
          level: QueryaMotionLevel.off,
          child: const material.Scaffold(
            body: ResultsTab(isLoading: true),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        resultsShell(
          level: QueryaMotionLevel.off,
          child: const material.Scaffold(
            body: ResultsTab(errorMessage: 'boom'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const material.ValueKey('results_mode_loading')),
        findsNothing,
      );
      expect(
        find.byKey(const material.ValueKey('results_mode_error')),
        findsOneWidget,
      );
    });

    testWidgets('grid row updates do not change mode key', (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(
              columns: ['id'],
              rows: [
                ['1'],
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const material.ValueKey('results_mode_grid')),
        findsOneWidget,
      );

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(
              columns: ['id'],
              rows: [
                ['1'],
                ['2'],
                ['3'],
              ],
            ),
          ),
        ),
      );
      await tester.pump();
      // Same mode key — no second grid body from a mode switch.
      expect(
        find.byKey(const material.ValueKey('results_mode_grid')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('shows status and affected empty modes', (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(statusLine: 'Connected to db'),
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const material.ValueKey('results_mode_status')),
        findsOneWidget,
      );
      expect(find.text('Connected to db'), findsOneWidget);

      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: ResultsTab(affectedRows: 4),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const material.ValueKey('results_mode_affected')),
        findsOneWidget,
      );
      expect(find.text('Rows affected: 4'), findsOneWidget);
    });

    testWidgets('allows manual column drag-resizing in VirtualResultGrid',
        (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: material.SizedBox(
              width: 800,
              height: 400,
              child: VirtualResultGrid(
                columns: ['id', 'username', 'email'],
                rows: [
                  ['1', 'alice', 'alice@example.com'],
                  ['2', 'bob', 'bob@example.com'],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('id'), findsOneWidget);
      expect(find.text('username'), findsOneWidget);
      expect(find.text('email'), findsOneWidget);

      // Verify resize handles are rendered with resizeColumn cursor
      final resizeRegions = find.byWidgetPredicate(
        (w) =>
            w is material.MouseRegion &&
            w.cursor == material.SystemMouseCursors.resizeColumn,
      );
      expect(resizeRegions, findsNWidgets(3));

      // Drag the first column handle by +50 pixels
      final firstHandle = resizeRegions.first;
      final startCenter = tester.getCenter(firstHandle);
      await tester.dragFrom(startCenter, const material.Offset(50, 0));
      await tester.pumpAndSettle();

      // Column headers and rows remain stable and rendered
      expect(find.text('alice'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
    });

    testWidgets('allows sorting by clicking column headers in VirtualResultGrid',
        (tester) async {
      await tester.pumpWidget(
        resultsShell(
          child: const material.Scaffold(
            body: material.SizedBox(
              width: 800,
              height: 400,
              child: VirtualResultGrid(
                columns: ['id', 'score'],
                rows: [
                  ['1', '100'],
                  ['2', '20'],
                  ['3', '500'],
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap on 'score' header -> Ascending sort
      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      // Arrow up icon should appear
      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsOneWidget);

      // Tap again -> Descending sort
      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      // Arrow down icon should appear
      expect(find.byIcon(material.Icons.arrow_downward_rounded), findsOneWidget);

      // Tap again -> Reset to natural order
      await tester.tap(find.text('score'));
      await tester.pumpAndSettle();

      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(material.Icons.arrow_downward_rounded), findsNothing);
    });

    testWidgets('renders DataGridStagingToolbar and updates on add/delete/revert',
        (tester) async {
      final staging = DataGridStagingBuffer(
        columns: ['id', 'name'],
        rows: [
          ['1', 'Alice'],
          ['2', 'Bob'],
        ],
      );

      var appliedChanges = 0;

      await tester.pumpWidget(
        resultsShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 800,
              height: 500,
              child: ResultsTab(
                columns: const ['id', 'name'],
                rows: const [
                  ['1', 'Alice'],
                  ['2', 'Bob'],
                ],
                stagingBuffer: staging,
                onApplyChanges: () => appliedChanges++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify DataGridStagingToolbar is rendered
      expect(find.byType(DataGridStagingToolbar), findsOneWidget);
      expect(find.text('No changes'), findsOneWidget);
      expect(find.text('Add Row'), findsOneWidget);

      // Tap 'Add Row' -> appends a new row
      await tester.tap(find.text('Add Row'));
      await tester.pumpAndSettle();

      expect(staging.isDirty, isTrue);
      expect(staging.totalRowCount, 3);
      expect(find.text('1 pending change'), findsOneWidget);
      expect(find.text('Revert All'), findsOneWidget);

      // Tap 'Revert All' -> resets buffer
      await tester.tap(find.text('Revert All'));
      await tester.pumpAndSettle();

      expect(staging.isDirty, isFalse);
      expect(staging.totalRowCount, 2);
      expect(find.text('No changes'), findsOneWidget);

      // Select row 0 in grid
      await tester.tap(find.text('Alice'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();

      // Tap 'Delete Row' in toolbar
      await tester.tap(find.text('Delete Row'));
      await tester.pumpAndSettle();

      expect(staging.isDirty, isTrue);
      expect(staging.deletedRowCount, 1);
      expect(find.text('Restore Row'), findsOneWidget);

      // Save button should now be enabled; tap it
      await tester.ensureVisible(find.text('Save Changes'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(appliedChanges, 1);
    });
  });
}
