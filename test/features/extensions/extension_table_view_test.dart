import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/extensions/models/extension_driver_capabilities.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';

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

    test('Extension driver mutation response validation requires integer affectedRows == 1', () {
      // 1. Missing affectedRows count
      void validateResponse(dynamic res) {
        if (res is! Map) throw StateError('Response is not map');
        final affected = res['affectedRows'];
        if (affected is! int) {
          throw StateError('Save failed: driver did not return an affectedRows count.');
        }
        expectDmlMatchedRows(affected);
      }

      expect(
        () => validateResponse({}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Save failed: driver did not return an affectedRows count.'),
        )),
      );

      // 2. Non-integer affectedRows
      expect(
        () => validateResponse({'affectedRows': '1'}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Save failed: driver did not return an affectedRows count.'),
        )),
      );

      // 3. Zero affectedRows matches no rows (expectDmlMatchedRows throws)
      expect(
        () => validateResponse({'affectedRows': 0}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('Save failed: a statement matched 0 rows.'),
        )),
      );

      // 4. Multiple matched rows would silently rewrite duplicates
      expect(
        () => validateResponse({'affectedRows': 3}),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          contains('matched 3 rows instead of 1'),
        )),
      );

      // 5. Exactly one affected row succeeds
      expect(() => validateResponse({'affectedRows': 1}), returnsNormally);
    });

    test('Schema fetch failure is captured as unavailable and disables staging', () async {
      final failedLoad = await loadTableViewSchema(() async {
        throw StateError('Extension driver rpc timeout');
      });

      expect(failedLoad.isOk, isFalse);
      expect(failedLoad.error, isA<StateError>());

      final enabled = tableViewEditingEnabled(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: false,
        readOnly: false,
        schemaError: failedLoad.error,
      );
      expect(enabled, isFalse);

      final reason = tableViewEditDisabledReason(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: false,
        schemaLoaded: true,
        readOnly: false,
        schemaError: failedLoad.error,
      );
      expect(reason, contains('Cannot edit: schema unavailable.'));
      expect(reason, contains('Extension driver rpc timeout'));
    });

    test('Table without primary keys disables staging with no PK reason', () async {
      final successLoad = await loadTableViewSchema(() async {
        return const TableSchemaMeta(tableName: 'logs', columns: [], primaryKeys: []);
      });

      expect(successLoad.isOk, isTrue);
      expect(successLoad.schema!.primaryKeys, isEmpty);

      final enabled = tableViewEditingEnabled(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: successLoad.schema!.primaryKeys.isNotEmpty,
        readOnly: false,
        schemaError: null,
      );
      expect(enabled, isFalse);

      final reason = tableViewEditDisabledReason(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: successLoad.schema!.primaryKeys.isNotEmpty,
        schemaLoaded: true,
        readOnly: false,
        schemaError: null,
      );
      expect(reason, 'Cannot edit: no primary key detected');
    });

    test('Table with primary key and mutation support enables staging', () async {
      final successLoad = await loadTableViewSchema(() async {
        return const TableSchemaMeta(
          tableName: 'users',
          columns: [],
          primaryKeys: ['id'],
        );
      });

      expect(successLoad.isOk, isTrue);
      expect(successLoad.schema!.primaryKeys, ['id']);

      final enabled = tableViewEditingEnabled(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: successLoad.schema!.primaryKeys.isNotEmpty,
        readOnly: false,
        schemaError: null,
      );
      expect(enabled, isTrue);

      final reason = tableViewEditDisabledReason(
        isView: false,
        customSqlActive: false,
        hasPrimaryKey: successLoad.schema!.primaryKeys.isNotEmpty,
        schemaLoaded: true,
        readOnly: false,
        schemaError: null,
      );
      expect(reason, isNull);
    });
  });
}
