import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/main_screen/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/main_screen/grid_filter_engine.dart';
import 'package:querya_desktop/features/main_screen/grid_groupings_engine.dart';
import 'package:querya_desktop/features/main_screen/grid_selection_calc_engine.dart';

void main() {
  group('Data Grid End-to-End Integration Tests', () {
    const columns = ['id', 'username', 'email', 'balance', 'status'];
    final baseRows = [
      ['1', 'alice', 'alice@example.com', '150.00', 'ACTIVE'],
      ['2', 'bob', 'bob@example.com', '50.00', 'PENDING'],
      ['3', 'charlie', 'charlie@example.com', '300.00', 'ACTIVE'],
      ['4', 'david', 'david@example.com', '0.00', 'CANCELLED'],
    ];

    test('E2E: Staging workflow -> Plan generation -> Multi-dialect DML compilation', () {
      final buffer = DataGridStagingBuffer(
        columns: columns,
        rows: baseRows,
      );

      expect(buffer.isDirty, isFalse);

      // 1. Modify cell (Row 0, balance: 150.00 -> 250.00)
      buffer.setCell(0, 3, '250.00');
      // 2. Modify cell (Row 1, status: PENDING -> ACTIVE)
      buffer.setCell(1, 4, 'ACTIVE');
      // 3. Mark Row 3 as deleted
      buffer.toggleDeleteRow(3);
      // 4. Insert new row
      buffer.addRow(['5', 'eve', 'eve@example.com', '500.00', 'ACTIVE']);

      expect(buffer.isDirty, isTrue);
      expect(buffer.modifiedCells.length, equals(2));
      expect(buffer.deletedRowIndices, contains(3));
      expect(buffer.insertedRows.length, equals(1));

      // 5. Generate Postgres mutation plan with primary key 'id'
      final pgPlan = buffer.generateMutationPlan(
        dialect: SqlDialect.postgres,
        tableName: 'users',
        primaryKeys: ['id'],
      );

      expect(pgPlan.statements.length, equals(4));
      expect(pgPlan.statements[0].sql, contains('UPDATE "users" SET "balance" = 250.00 WHERE "id" = 1'));
      expect(pgPlan.statements[1].sql, contains('UPDATE "users" SET "status" = \'ACTIVE\' WHERE "id" = 2'));
      expect(pgPlan.statements[2].sql, contains('INSERT INTO "users"'));
      expect(pgPlan.statements[3].sql, contains('DELETE FROM "users" WHERE "id" = 4'));
      expect(pgPlan.toTransactionSql(), startsWith('BEGIN;\n'));
      expect(pgPlan.toTransactionSql(), contains('COMMIT;'));

      // 6. Generate MySQL mutation plan
      final mysqlPlan = buffer.generateMutationPlan(
        dialect: SqlDialect.mysql,
        tableName: 'users',
        primaryKeys: ['id'],
      );
      expect(mysqlPlan.statements[0].sql, contains('UPDATE `users` SET `balance` = 250.00 WHERE `id` = 1'));
      expect(mysqlPlan.toTransactionSql(), startsWith('START TRANSACTION;\n'));

      // 7. Generate SQLite mutation plan
      final sqlitePlan = buffer.generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: 'users',
        primaryKeys: ['id'],
      );
      expect(sqlitePlan.statements[0].sql, contains('UPDATE "users" SET "balance" = 250.00 WHERE "id" = 1'));
      expect(sqlitePlan.toTransactionSql(), startsWith('BEGIN TRANSACTION;\n'));

      // 8. Reset / clear on successful commit
      buffer.revertAll();
      expect(buffer.isDirty, isFalse);
      expect(buffer.modifiedCells, isEmpty);
      expect(buffer.insertedRows, isEmpty);
      expect(buffer.deletedRowIndices, isEmpty);
    });

    test('E2E: SQL Query -> Target Extractor -> Schema & Table resolution', () {
      expect(
        SqlTableTargetExtractor.extract('SELECT * FROM users'),
        equals(const SqlTableTarget(tableName: 'users')),
      );

      expect(
        SqlTableTargetExtractor.extract('SELECT id, name FROM public.accounts WHERE active = 1'),
        equals(const SqlTableTarget(tableName: 'accounts', schema: 'public')),
      );

      expect(
        SqlTableTargetExtractor.extract('SELECT u.id FROM `my_db`.`customers` u ORDER BY id DESC'),
        equals(const SqlTableTarget(tableName: 'customers', schema: 'my_db')),
      );

      // Complex join / non-simple select should return null
      expect(
        SqlTableTargetExtractor.extract('SELECT a.id, b.name FROM a JOIN b ON a.id = b.id'),
        isNull,
      );
    });

    test('E2E: Filter Engine -> Selection Calc -> Groupings Pivot pipeline', () {
      // 1. Filter rows where status is ACTIVE or PENDING and balance > 0
      final matchingIndices = GridFilterEngine.filterRowIndices(
        filterText: "status IN ('ACTIVE', 'PENDING') AND balance > 0",
        columns: columns,
        rows: baseRows,
      );
      expect(matchingIndices, equals([0, 1, 2]));

      final filteredRows = matchingIndices.map((i) => baseRows[i]).toList();

      // 2. Select balance column values from filtered rows
      final balanceValues = filteredRows.map((r) => r[3]).toList();
      final stats = GridSelectionCalcEngine.compute(balanceValues);

      expect(stats.totalCount, equals(3));
      expect(stats.sum, equals(500.00));
      expect(stats.average, closeTo(166.666, 0.01));
      expect(stats.median, equals(150.00));
      expect(stats.min, equals(50.00));
      expect(stats.max, equals(300.00));

      // 3. Group filtered rows by status with SUM(balance) aggregation
      final groups = GridGroupingsEngine.buildGroups(
        groupColIndices: [4],
        rows: filteredRows,
        aggConfig: const GroupAggregationConfig(
          aggType: GroupingAggType.sum,
          targetColIndex: 3,
        ),
      );

      expect(groups.length, equals(2));
      final activeGroup = groups.firstWhere((g) => g.groupKey == 'ACTIVE');
      expect(activeGroup.count, equals(2));
      expect(activeGroup.aggValue, equals(450.00));

      final pendingGroup = groups.firstWhere((g) => g.groupKey == 'PENDING');
      expect(pendingGroup.count, equals(1));
      expect(pendingGroup.aggValue, equals(50.00));

      // 4. Export pivot summary to CSV
      final csv = GridGroupingsEngine.exportPivotToCsv(
        groups: groups,
        groupByColumnName: 'status',
      );
      expect(csv, contains('"ACTIVE",2,66.67%,450.00'));
      expect(csv, contains('"PENDING",1,33.33%,50.00'));
    });
  });
}
