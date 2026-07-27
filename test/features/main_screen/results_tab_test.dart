import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/motion/querya_fade_slide.dart';
import 'package:querya_desktop/core/motion/querya_motion_scope.dart';
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
  });
}
