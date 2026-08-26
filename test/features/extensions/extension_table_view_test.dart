import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/extensions/models/extension_driver_capabilities.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';

void main() {
  group('ExtensionDriver Mutation Standard & Staging', () {
    test('ExtensionDriverCapabilities default vs mutation flags', () {
      const defaultCaps = ExtensionDriverCapabilities();
      expect(defaultCaps.supportsMutations, isFalse);
      expect(defaultCaps.supportsBatchMutations, isFalse);

      final capsWithMutations = ExtensionDriverCapabilities.fromRpc({
        'supports_mutations': true,
        'supports_batch_mutations': true,
      });
      expect(capsWithMutations.supportsMutations, isTrue);
      expect(capsWithMutations.supportsBatchMutations, isTrue);
    });

    test('DataGridStagingBuffer generates valid mutation payload for ExtensionDriver mutate standard', () {
      final buffer = DataGridStagingBuffer(
        columns: ['id', 'email', 'status'],
        rows: [
          ['1', 'alice@test.com', 'active'],
          ['2', 'bob@test.com', 'pending'],
        ],
      );

      // 1. Stage update on row 0, col 1 (email)
      buffer.setCell(0, 1, 'alice_new@test.com');

      // 2. Stage delete on row 1
      buffer.toggleDeleteRow(1);

      // 3. Stage insert
      buffer.addRow(['3', 'carol@test.com', 'active']);

      expect(buffer.isDirty, isTrue);
      expect(buffer.changeCount, 3);

      final mutations = <Map<String, dynamic>>[];

      // Replicate ExtensionTableView mutation mapping logic
      final columns = buffer.columns;

      for (final entry in buffer.modifiedCells.entries) {
        final rowIndex = entry.key;
        final colMap = entry.value;
        final origRow = buffer.originalRows[rowIndex];

        final whereMap = <String, dynamic>{
          columns[0]: origRow[0],
        };

        final setMap = <String, dynamic>{};
        for (final colEntry in colMap.entries) {
          final colName = columns[colEntry.key];
          final val = colEntry.value;
          setMap[colName] = val == TableMutationEngine.kNullSentinel ? null : val;
        }

        mutations.add({
          'type': 'update',
          'where': whereMap,
          'set': setMap,
        });
      }

      for (final row in buffer.insertedRows) {
        final valuesMap = <String, dynamic>{};
        for (var c = 0; c < columns.length; c++) {
          final val = c < row.length ? row[c] : null;
          valuesMap[columns[c]] =
              (val == null || val == TableMutationEngine.kNullSentinel || val == 'NULL')
                  ? null
                  : val;
        }
        mutations.add({
          'type': 'insert',
          'values': valuesMap,
        });
      }

      for (final rowIndex in buffer.deletedRowIndices) {
        final origRow = buffer.originalRows[rowIndex];
        final whereMap = <String, dynamic>{
          columns[0]: origRow[0],
        };
        mutations.add({
          'type': 'delete',
          'where': whereMap,
        });
      }

      expect(mutations.length, 3);
      expect(mutations[0]['type'], 'update');
      expect(mutations[0]['where'], {'id': '1'});
      expect(mutations[0]['set'], {'email': 'alice_new@test.com'});

      expect(mutations[1]['type'], 'insert');
      expect(mutations[1]['values'], {'id': '3', 'email': 'carol@test.com', 'status': 'active'});

      expect(mutations[2]['type'], 'delete');
      expect(mutations[2]['where'], {'id': '2'});
    });
  });
}
