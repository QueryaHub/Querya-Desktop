import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/result_grid_view.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

material.Widget _testShell({required material.Widget child}) {
  final td = QueryaTheme.darkDefault
      .toShadcnThemeData()
      .copyWith(platform: () => TargetPlatform.linux);
  return ShadcnApp(
    theme: td,
    home: material.Scaffold(
      body: child,
    ),
  );
}

Future<void> _secondaryClick(WidgetTester tester, Finder finder) async {
  final gesture = await tester.startGesture(
    tester.getCenter(finder),
    buttons: kSecondaryMouseButton,
  );
  await gesture.up();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('sortResultGridRowsWithIndices', () {
    test('returns sorted rows and preserves 1-to-1 model indices', () {
      final rows = [
        ['Charlie', '30'],
        ['Alice', '10'],
        ['Bob', '20'],
      ];

      final result = sortResultGridRowsWithIndices(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
      );

      // Expected sorted: Alice (index 1), Bob (index 2), Charlie (index 0)
      expect(result.rows[0][0], equals('Alice'));
      expect(result.rows[1][0], equals('Bob'));
      expect(result.rows[2][0], equals('Charlie'));

      expect(result.sortedToModelIndices, equals([1, 2, 0]));

      // Descending
      final resultDesc = sortResultGridRowsWithIndices(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.descending,
      );

      expect(resultDesc.rows[0][0], equals('Charlie'));
      expect(resultDesc.rows[1][0], equals('Bob'));
      expect(resultDesc.rows[2][0], equals('Alice'));

      expect(resultDesc.sortedToModelIndices, equals([0, 2, 1]));
    });

    test('handles numeric column sorting with indices', () {
      final rows = [
        ['Item 1', '100'],
        ['Item 2', '25'],
        ['Item 3', '5'],
      ];

      final result = sortResultGridRowsWithIndices(
        rows: rows,
        columnIndex: 1,
        order: ResultGridSortOrder.ascending,
      );

      // Numeric order: 5 (model 2), 25 (model 1), 100 (model 0)
      expect(result.rows[0][1], equals('5'));
      expect(result.rows[1][1], equals('25'));
      expect(result.rows[2][1], equals('100'));
      expect(result.sortedToModelIndices, equals([2, 1, 0]));
    });

    test('sortResultGridRowsWithIndicesAdaptive correctly sorts below and above isolate threshold', () async {
      final rows = [
        ['3', 'Charlie'],
        ['1', 'Alice'],
        ['2', 'Bob'],
      ];

      // Below threshold (synchronous branch)
      final resSync = await sortResultGridRowsWithIndicesAdaptive(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
        threshold: 10,
      );
      expect(resSync.rows[0][1], equals('Alice'));
      expect(resSync.rows[1][1], equals('Bob'));
      expect(resSync.rows[2][1], equals('Charlie'));
      expect(resSync.sortedToModelIndices, equals([1, 2, 0]));

      // Above threshold (isolate compute branch)
      final resCompute = await sortResultGridRowsWithIndicesAdaptive(
        rows: rows,
        columnIndex: 0,
        order: ResultGridSortOrder.ascending,
        threshold: 2,
      );
      expect(resCompute.rows[0][1], equals('Alice'));
      expect(resCompute.rows[1][1], equals('Bob'));
      expect(resCompute.rows[2][1], equals('Charlie'));
      expect(resCompute.sortedToModelIndices, equals([1, 2, 0]));
    });
  });

  group('VirtualResultGrid active sorting staging mutation integrity', () {
    testWidgets('deleting visual row 0 after sorting marks the correct model row deleted',
        (tester) async {
      final columns = ['name', 'age'];
      final rawRows = [
        ['Charlie', '30'], // Model index 0
        ['Alice', '10'],   // Model index 1
        ['Bob', '20'],     // Model index 2
      ];

      final stagingBuffer = DataGridStagingBuffer(
        columns: columns,
        rows: rawRows,
      );

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 600,
            child: VirtualResultGrid(
              columns: columns,
              rows: stagingBuffer.effectiveRows,
              stagingBuffer: stagingBuffer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Click header "name" to sort ascending
      // Visual order will become: Alice (model 1), Bob (model 2), Charlie (model 0)
      final nameHeader = find.text('name');
      expect(nameHeader, findsOneWidget);
      await tester.tap(nameHeader);
      await tester.pumpAndSettle();

      // Verify sort arrow appears
      expect(find.byIcon(material.Icons.arrow_upward_rounded), findsOneWidget);

      // Secondary click visual row 0 (Alice) to open context menu
      final aliceCell = find.text('Alice');
      expect(aliceCell, findsOneWidget);
      await _secondaryClick(tester, aliceCell);

      // Tap Delete Row in context menu
      final deleteMenuItem = find.text('Delete Row');
      expect(deleteMenuItem, findsOneWidget);
      await tester.tap(deleteMenuItem);
      await tester.pumpAndSettle();

      // Verify that model row 1 ('Alice') is marked deleted, NOT model row 0 ('Charlie')!
      expect(stagingBuffer.getRowStatus(1), equals(StagedRowStatus.deleted),
          reason: 'Model row 1 (Alice) must be marked as deleted');
      expect(stagingBuffer.getRowStatus(0), equals(StagedRowStatus.unchanged),
          reason: 'Model row 0 (Charlie) must NOT be deleted');
      expect(stagingBuffer.getRowStatus(2), equals(StagedRowStatus.unchanged),
          reason: 'Model row 2 (Bob) must NOT be deleted');
    });

    testWidgets('setting NULL on visual row 0 after sorting mutates the correct model row',
        (tester) async {
      final columns = ['name', 'age'];
      final rawRows = [
        ['Charlie', '30'], // Model index 0
        ['Alice', '10'],   // Model index 1
        ['Bob', '20'],     // Model index 2
      ];

      final stagingBuffer = DataGridStagingBuffer(
        columns: columns,
        rows: rawRows,
      );

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 600,
            child: VirtualResultGrid(
              columns: columns,
              rows: stagingBuffer.effectiveRows,
              stagingBuffer: stagingBuffer,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Sort ascending by name: visual row 0 is Alice (model 1)
      await tester.tap(find.text('name'));
      await tester.pumpAndSettle();

      // Secondary click Alice cell (visual row 0, col 0)
      await _secondaryClick(tester, find.text('Alice'));

      // Tap "Set NULL"
      final setNullMenuItem = find.text('Set NULL');
      expect(setNullMenuItem, findsOneWidget);
      await tester.tap(setNullMenuItem);
      await tester.pumpAndSettle();

      // Verify model row 1 is modified to null sentinel, model row 0 is untouched
      expect(stagingBuffer.getCellStatus(1, 0), equals(StagedCellStatus.modified));
      expect(stagingBuffer.isCellNull(1, 0), isTrue);
      expect(stagingBuffer.getCellStatus(0, 0), equals(StagedCellStatus.clean));
      expect(stagingBuffer.getCellValue(0, 0), equals('Charlie'));
    });
  });

  group('VirtualResultGrid keeps sorted order stable while editing (#875)', () {
    Future<DataGridStagingBuffer> pumpSorted(
      WidgetTester tester, {
      required bool rebuildParent,
    }) async {
      final columns = ['name', 'age'];
      final buffer = DataGridStagingBuffer(
        columns: columns,
        rows: [
          ['Charlie', '30'], // model 0
          ['Alice', '10'], // model 1
          ['Bob', '20'], // model 2
        ],
      );
      addTearDown(buffer.dispose);

      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 600,
            child: rebuildParent
                // Like ResultsTab: a fresh `rows` list on every buffer change.
                ? material.ListenableBuilder(
                    listenable: buffer,
                    builder: (_, __) => VirtualResultGrid(
                      columns: columns,
                      rows: buffer.effectiveRows,
                      stagingBuffer: buffer,
                    ),
                  )
                : VirtualResultGrid(
                    columns: columns,
                    rows: buffer.effectiveRows,
                    stagingBuffer: buffer,
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('name'));
      await tester.pumpAndSettle();
      return buffer;
    }

    double y(WidgetTester tester, String text) =>
        tester.getTopLeft(find.text(text)).dy;

    for (final rebuildParent in [false, true]) {
      testWidgets(
          'editing a cell keeps the row in place and shows the new value '
          '(parent rebuilds: $rebuildParent)', (tester) async {
        final buffer = await pumpSorted(tester, rebuildParent: rebuildParent);
        // Sorted ascending: Alice, Bob, Charlie.
        expect(y(tester, 'Alice') < y(tester, 'Bob'), isTrue);

        buffer.setCell(1, 0, 'Zed'); // Alice -> Zed (model row 1)
        await tester.pumpAndSettle();

        expect(find.text('Alice'), findsNothing);
        // Zed stays first instead of jumping below Charlie.
        expect(y(tester, 'Zed') < y(tester, 'Bob'), isTrue);
        expect(y(tester, 'Bob') < y(tester, 'Charlie'), isTrue);
      });

      testWidgets(
          'edits keep mapping visual rows to the right model row '
          '(parent rebuilds: $rebuildParent)', (tester) async {
        final buffer = await pumpSorted(tester, rebuildParent: rebuildParent);

        buffer.setCell(1, 1, '99');
        await tester.pumpAndSettle();
        await _secondaryClick(tester, find.text('Alice'));
        await tester.tap(find.text('Delete Row'));
        await tester.pumpAndSettle();

        expect(buffer.getRowStatus(1), StagedRowStatus.deleted);
        expect(buffer.getRowStatus(0), StagedRowStatus.unchanged);
      });
    }

    testWidgets('inserting a row still re-sorts', (tester) async {
      final buffer = await pumpSorted(tester, rebuildParent: true);

      buffer.addRow(['Aaron', '5']);
      await tester.pumpAndSettle();

      expect(y(tester, 'Aaron') < y(tester, 'Alice'), isTrue);
    });
  });

  group('VirtualResultGrid horizontal scroll rebuilds (#879)', () {
    const colCount = 40;
    final columns = [for (var c = 0; c < colCount; c++) 'column_$c'];
    final rows = [
      for (var r = 0; r < 5; r++) [for (var c = 0; c < colCount; c++) 'v${r}_$c'],
    ];

    Future<void> pumpWide(WidgetTester tester) async {
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 600,
            height: 400,
            child: VirtualResultGrid(columns: columns, rows: rows),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder firstRow() => find.byKey(const material.ValueKey('result-row-0'));

    Finder hScrollable() => find.byWidgetPredicate(
          (w) => w is Scrollable && w.axis == Axis.horizontal,
        );

    testWidgets('a small pan inside the same column window does not rebuild rows',
        (tester) async {
      await pumpWide(tester);
      final before = tester.widget(firstRow());
      expect(find.text('column_0'), findsOneWidget);

      // A few pixels stays inside the current (overscanned) window.
      final position = tester.state<ScrollableState>(hScrollable()).position;
      position.jumpTo(3);
      await tester.pump();
      expect(position.pixels, 3);

      expect(identical(tester.widget(firstRow()), before), isTrue,
          reason: 'rows must not be rebuilt for a pan that keeps the window');
      await tester.pumpAndSettle(); // let the scrollbar fade timer finish
    });

    testWidgets('panning far enough builds the newly visible columns',
        (tester) async {
      await pumpWide(tester);
      expect(find.text('column_39'), findsNothing);

      final position = tester.state<ScrollableState>(hScrollable()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();

      expect(find.text('column_39'), findsOneWidget);
      expect(find.text('v0_39'), findsOneWidget);
      expect(find.text('column_0'), findsNothing);
    });

    testWidgets('scrolling back restores the first columns', (tester) async {
      await pumpWide(tester);
      final position = tester.state<ScrollableState>(hScrollable()).position;
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      position.jumpTo(0);
      await tester.pumpAndSettle();

      expect(find.text('column_0'), findsOneWidget);
      expect(find.text('column_39'), findsNothing);
    });
  });

  group('VirtualResultGrid reuses unchanged rows and cells (#972)', () {
    // Wider than the viewport, so content edits do not re-distribute spare
    // column width (which legitimately rebuilds every row).
    final columns = [for (var c = 0; c < 30; c++) 'col_$c'];
    Future<DataGridStagingBuffer> pump(WidgetTester tester) async {
      final buffer = DataGridStagingBuffer(
        columns: columns,
        rows: [
          for (var r = 0; r < 6; r++) [for (var c = 0; c < 30; c++) 'r${r}c$c'],
        ],
      );
      addTearDown(buffer.dispose);
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 800,
            height: 600,
            child: material.ListenableBuilder(
              listenable: buffer,
              builder: (_, __) => VirtualResultGrid(
                columns: columns,
                rows: buffer.effectiveRows,
                stagingBuffer: buffer,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return buffer;
    }

    Widget rowWidget(WidgetTester tester, int i) =>
        tester.widget(find.byKey(material.ValueKey('result-row-$i')));

    testWidgets('editing one cell rebuilds only that row', (tester) async {
      final buffer = await pump(tester);
      final before = [for (var i = 0; i < 6; i++) rowWidget(tester, i)];

      buffer.setCell(2, 1, 'edited');
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        expect(identical(rowWidget(tester, i), before[i]), i != 2,
            reason: 'row $i');
      }
      expect(find.text('edited'), findsOneWidget);
    });

    testWidgets('a selection change only rebuilds rows in the old or new range',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('r1c0'));
      // onTap resolves only after the double-tap timeout.
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      final before = [for (var i = 0; i < 6; i++) rowWidget(tester, i)];

      // Arrow Down moves the selection from row 1 to row 2.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      for (var i = 0; i < 6; i++) {
        final touched = i == 1 || i == 2;
        expect(identical(rowWidget(tester, i), before[i]), !touched,
            reason: 'row $i');
      }
    });

    testWidgets('staged status changes still repaint the row', (tester) async {
      final buffer = await pump(tester);
      final before = rowWidget(tester, 3);

      buffer.toggleDeleteRow(3);
      await tester.pumpAndSettle();

      expect(identical(rowWidget(tester, 3), before), isFalse);
      expect(buffer.getRowStatus(3), StagedRowStatus.deleted);
    });

    testWidgets('cells that stay in the column window are reused on scroll',
        (tester) async {
      final wide = [for (var c = 0; c < 40; c++) 'column_$c'];
      final rows = [
        for (var r = 0; r < 3; r++) [for (var c = 0; c < 40; c++) 'v${r}_$c'],
      ];
      await tester.pumpWidget(
        _testShell(
          child: material.SizedBox(
            width: 600,
            height: 400,
            child: VirtualResultGrid(columns: wide, rows: rows),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Map<int, Widget> cells() {
        final out = <int, Widget>{};
        final rowFinder = find.byKey(const material.ValueKey('result-row-0'));
        for (var c = 0; c < 40; c++) {
          final f = find.descendant(
            of: rowFinder,
            matching: find.byKey(material.ValueKey<int>(c)),
          );
          if (f.evaluate().isNotEmpty) out[c] = tester.widget(f);
        }
        return out;
      }

      final before = cells();
      final position = tester
          .state<ScrollableState>(find.byWidgetPredicate(
              (w) => w is Scrollable && w.axis == Axis.horizontal))
          .position;
      position.jumpTo(1200); // far enough to shift the window
      await tester.pumpAndSettle();
      final after = cells();

      expect(after.keys.first, greaterThan(before.keys.first));
      final shared = before.keys.toSet().intersection(after.keys.toSet());
      expect(shared, isNotEmpty);
      for (final c in shared) {
        expect(identical(before[c], after[c]), isTrue, reason: 'column $c');
      }
    });
  });
}
