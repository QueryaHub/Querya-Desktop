import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' as material;
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
}
