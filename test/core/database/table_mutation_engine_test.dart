import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';

void main() {
  group('TableSchemaMeta', () {
    test('serializes and deserializes correctly', () {
      const meta = TableSchemaMeta(
        tableName: 'users',
        schema: 'public',
        columns: [
          TableColumnMeta(
            name: 'id',
            dataType: 'integer',
            isNullable: false,
            isPrimaryKey: true,
            primaryKeyPosition: 1,
          ),
          TableColumnMeta(
            name: 'email',
            dataType: 'varchar',
            isNullable: true,
          ),
        ],
        primaryKeys: ['id'],
      );

      final json = meta.toJson();
      final restored = TableSchemaMeta.fromJson(json);

      expect(restored.tableName, 'users');
      expect(restored.schema, 'public');
      expect(restored.hasPrimaryKey, isTrue);
      expect(restored.primaryKeys, ['id']);
      expect(restored.columns.length, 2);
      expect(restored.getColumn('id')?.isPrimaryKey, isTrue);
      expect(restored.getColumn('email')?.isNullable, isTrue);
    });
  });

  group('TableMutationEngine', () {
    const columns = ['id', 'username', 'age', 'active'];
    const originalRows = [
      ['1', 'alice', '30', 'true'],
      ['2', 'bob', '25', 'false'],
    ];

    test('generates UPDATE statement for modified cells with single PK in Postgres dialect', () {
      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.postgres,
        tableName: 'users',
        schema: 'public',
        columns: columns,
        primaryKeys: ['id'],
        originalRows: originalRows,
        modifiedCells: {
          0: {1: 'alice_updated', 2: '31'},
        },
        insertedRows: [],
        deletedRowIndices: {},
      );

      expect(plan.statementCount, 1);
      final stmt = plan.statements.first;
      expect(stmt.type, MutationType.update);
      expect(
        stmt.sql,
        'UPDATE "public"."users" SET "username" = \'alice_updated\', "age" = 31 WHERE "id" = 1',
      );

      final tx = plan.toTransactionSql();
      expect(tx.startsWith('BEGIN;'), isTrue);
      expect(tx.endsWith('COMMIT;\n'), isTrue);
    });

    test('generates UPDATE statement for MySQL dialect with backticks', () {
      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.mysql,
        tableName: 'users',
        schema: 'mydb',
        columns: columns,
        primaryKeys: ['id'],
        originalRows: originalRows,
        modifiedCells: {
          1: {3: 'true'},
        },
        insertedRows: [],
        deletedRowIndices: {},
      );

      expect(plan.statementCount, 1);
      final stmt = plan.statements.first;
      expect(stmt.type, MutationType.update);
      expect(
        stmt.sql,
        'UPDATE `mydb`.`users` SET `active` = TRUE WHERE `id` = 2',
      );

      final tx = plan.toTransactionSql();
      expect(tx.startsWith('START TRANSACTION;'), isTrue);
      expect(tx.contains('COMMIT;'), isTrue);
    });

    test('generates INSERT statement with NULL values in SQLite dialect', () {
      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.sqlite,
        tableName: 'users',
        columns: columns,
        primaryKeys: ['id'],
        originalRows: originalRows,
        modifiedCells: {},
        insertedRows: [
          ['3', 'charlie', 'NULL', 'false'],
        ],
        deletedRowIndices: {},
      );

      expect(plan.statementCount, 1);
      final stmt = plan.statements.first;
      expect(stmt.type, MutationType.insert);
      expect(
        stmt.sql,
        'INSERT INTO "users" ("id", "username", "age", "active") VALUES (3, \'charlie\', NULL, 0)',
      );

      final tx = plan.toTransactionSql();
      expect(tx.startsWith('BEGIN TRANSACTION;'), isTrue);
    });

    test('generates DELETE statement for deleted row index', () {
      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.postgres,
        tableName: 'users',
        schema: 'public',
        columns: columns,
        primaryKeys: ['id'],
        originalRows: originalRows,
        modifiedCells: {},
        insertedRows: [],
        deletedRowIndices: {0},
      );

      expect(plan.statementCount, 1);
      final stmt = plan.statements.first;
      expect(stmt.type, MutationType.delete);
      expect(stmt.sql, 'DELETE FROM "public"."users" WHERE "id" = 1');
    });

    test('handles composite primary keys in WHERE clause', () {
      const compositeCols = ['tenant_id', 'user_id', 'role'];
      const compositeRows = [
        ['100', '1', 'admin'],
      ];

      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.postgres,
        tableName: 'user_roles',
        columns: compositeCols,
        primaryKeys: ['tenant_id', 'user_id'],
        originalRows: compositeRows,
        modifiedCells: {
          0: {2: 'superadmin'},
        },
        insertedRows: [],
        deletedRowIndices: {},
      );

      expect(plan.statementCount, 1);
      expect(
        plan.statements.first.sql,
        'UPDATE "user_roles" SET "role" = \'superadmin\' WHERE "tenant_id" = 100 AND "user_id" = 1',
      );
    });

    test('falls back to all columns when no primary key is specified', () {
      const noPkCols = ['category', 'description'];
      const noPkRows = [
        ['sales', 'retail store'],
      ];

      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.postgres,
        tableName: 'tags',
        columns: noPkCols,
        primaryKeys: [],
        originalRows: noPkRows,
        modifiedCells: {
          0: {1: 'online store'},
        },
        insertedRows: [],
        deletedRowIndices: {},
      );

      expect(plan.statementCount, 1);
      expect(
        plan.statements.first.sql,
        'UPDATE "tags" SET "description" = \'online store\' WHERE "category" = \'sales\' AND "description" = \'retail store\'',
      );
    });

    test('preserves leading zeros and boolean strings in string columns with columnDataTypes', () {
      const stringCols = ['id', 'zip_code', 'is_flag_str'];
      const stringRows = [
        ['1', '01234', 'true'],
      ];

      final plan = TableMutationEngine.generatePlan(
        dialect: SqlDialect.postgres,
        tableName: 'addresses',
        columns: stringCols,
        primaryKeys: ['id'],
        originalRows: stringRows,
        modifiedCells: {
          0: {1: '00789', 2: 'false'},
        },
        insertedRows: [
          ['2', '04560', 'true'],
        ],
        deletedRowIndices: {},
        columnDataTypes: {
          'id': 'int',
          'zip_code': 'varchar(10)',
          'is_flag_str': 'text',
        },
      );

      expect(plan.statementCount, 2);
      expect(
        plan.statements[0].sql,
        'UPDATE "addresses" SET "zip_code" = \'00789\', "is_flag_str" = \'false\' WHERE "id" = 1',
      );
      expect(
        plan.statements[1].sql,
        'INSERT INTO "addresses" ("id", "zip_code", "is_flag_str") VALUES (2, \'04560\', \'true\')',
      );
    });

    test('preserves leading zeros in fallback heuristic without columnDataTypes', () {
      expect(
        TableMutationEngine.formatLiteral('01234', SqlDialect.postgres),
        '\'01234\'',
      );
      expect(
        TableMutationEngine.formatLiteral('007', SqlDialect.mysql),
        '\'007\'',
      );
      expect(
        TableMutationEngine.formatLiteral('0', SqlDialect.sqlite),
        '0',
      );
      expect(
        TableMutationEngine.formatLiteral('123', SqlDialect.postgres),
        '123',
      );
    });
  });
}
