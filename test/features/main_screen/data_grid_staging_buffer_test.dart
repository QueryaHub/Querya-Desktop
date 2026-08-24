import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';

void main() {
  group('DataGridStagingBuffer', () {
    late DataGridStagingBuffer buffer;

    setUp(() {
      buffer = DataGridStagingBuffer(
        columns: ['id', 'name', 'email'],
        rows: [
          ['1', 'Alice', 'alice@test.com'],
          ['2', 'Bob', 'bob@test.com'],
          ['3', 'Charlie', 'charlie@test.com'],
        ],
      );
    });

    test('initial state is clean and non-dirty', () {
      expect(buffer.isDirty, isFalse);
      expect(buffer.changeCount, 0);
      expect(buffer.totalRowCount, 3);
      expect(buffer.getRowStatus(0), StagedRowStatus.unchanged);
      expect(buffer.getCellStatus(0, 1), StagedCellStatus.clean);
      expect(buffer.getCellValue(0, 1), 'Alice');
      expect(buffer.getOriginalCellValue(0, 1), 'Alice');
    });

    test('modifying cell sets dirty and updates cell value', () {
      buffer.setCell(0, 1, 'Alice Cooper');

      expect(buffer.isDirty, isTrue);
      expect(buffer.changeCount, 1);
      expect(buffer.modifiedCellCount, 1);
      expect(buffer.getCellValue(0, 1), 'Alice Cooper');
      expect(buffer.getOriginalCellValue(0, 1), 'Alice');
      expect(buffer.getCellStatus(0, 1), StagedCellStatus.modified);
      expect(buffer.getRowStatus(0), StagedRowStatus.modified);

      // Reverting cell value to original clears dirty status
      buffer.setCell(0, 1, 'Alice');
      expect(buffer.isDirty, isFalse);
      expect(buffer.changeCount, 0);
      expect(buffer.getCellStatus(0, 1), StagedCellStatus.clean);
      expect(buffer.getRowStatus(0), StagedRowStatus.unchanged);
    });

    test('adding row appends inserted row and increments row count', () {
      final newIdx = buffer.addRow(['4', 'Diana', 'diana@test.com']);

      expect(newIdx, 3);
      expect(buffer.totalRowCount, 4);
      expect(buffer.isDirty, isTrue);
      expect(buffer.insertedRowCount, 1);
      expect(buffer.getRowStatus(3), StagedRowStatus.inserted);
      expect(buffer.getCellValue(3, 1), 'Diana');
      expect(buffer.getOriginalCellValue(3, 1), isNull);

      // Modifying cell in inserted row
      buffer.setCell(3, 1, 'Diana Prince');
      expect(buffer.getCellValue(3, 1), 'Diana Prince');
    });

    test('toggling delete row marks row deleted or removes inserted row', () {
      // Delete baseline row
      buffer.toggleDeleteRow(1);
      expect(buffer.isDirty, isTrue);
      expect(buffer.deletedRowCount, 1);
      expect(buffer.getRowStatus(1), StagedRowStatus.deleted);

      // Toggle again restores it
      buffer.toggleDeleteRow(1);
      expect(buffer.isDirty, isFalse);
      expect(buffer.deletedRowCount, 0);
      expect(buffer.getRowStatus(1), StagedRowStatus.unchanged);

      // Insert row and then delete it -> removes from inserted list
      final insIdx = buffer.addRow(['4', 'New', 'new@test.com']);
      expect(buffer.totalRowCount, 4);
      buffer.toggleDeleteRow(insIdx);
      expect(buffer.totalRowCount, 3);
      expect(buffer.isDirty, isFalse);
    });

    test('revertCell, revertRow, and revertAll restore pristine state', () {
      buffer.setCell(0, 1, 'Alice Modified');
      buffer.setCell(0, 2, 'modified@test.com');
      buffer.toggleDeleteRow(1);
      buffer.addRow(['4', 'Extra', 'extra@test.com']);

      expect(buffer.isDirty, isTrue);
      expect(buffer.changeCount, 4); // 2 cells + 1 deleted row + 1 inserted row

      // Revert single cell
      buffer.revertCell(0, 1);
      expect(buffer.getCellValue(0, 1), 'Alice');
      expect(buffer.getCellValue(0, 2), 'modified@test.com');

      // Revert whole row 0
      buffer.revertRow(0);
      expect(buffer.getCellValue(0, 2), 'alice@test.com');
      expect(buffer.getRowStatus(0), StagedRowStatus.unchanged);

      // Revert all
      buffer.revertAll();
      expect(buffer.isDirty, isFalse);
      expect(buffer.changeCount, 0);
      expect(buffer.totalRowCount, 3);
    });

    test('effectiveRows computes combined snapshot accurately', () {
      buffer.setCell(0, 1, 'Alice Updated');
      buffer.addRow(['4', 'David', 'david@test.com']);

      final eff = buffer.effectiveRows;
      expect(eff.length, 4);
      expect(eff[0], ['1', 'Alice Updated', 'alice@test.com']);
      expect(eff[1], ['2', 'Bob', 'bob@test.com']);
      expect(eff[2], ['3', 'Charlie', 'charlie@test.com']);
      expect(eff[3], ['4', 'David', 'david@test.com']);
    });
  });
}
