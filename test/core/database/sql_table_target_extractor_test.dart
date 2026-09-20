import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';

void main() {
  group('SqlTableTargetExtractor', () {
    test('extracts table name from simple SELECT', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM users');
      expect(target, isNotNull);
      expect(target!.tableName, 'users');
      expect(target.schema, isNull);
    });

    test('extracts schema and table from quoted identifiers', () {
      final target = SqlTableTargetExtractor.extract(
          'SELECT id, name FROM "public"."accounts" WHERE id > 10');
      expect(target, isNotNull);
      expect(target!.tableName, 'accounts');
      expect(target.schema, 'public');
    });

    test('extracts schema and table from MySQL backticks', () {
      final target = SqlTableTargetExtractor.extract(
          'SELECT * FROM `shop_db`.`orders` ORDER BY date DESC');
      expect(target, isNotNull);
      expect(target!.tableName, 'orders');
      expect(target.schema, 'shop_db');
    });

    test('extracts public.t from a simple qualified FROM', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM public.t');
      expect(target, const SqlTableTarget(tableName: 't', schema: 'public'));
    });

    test('returns null for queries with JOINs to avoid ambiguous mutations',
        () {
      final target = SqlTableTargetExtractor.extract(
          'SELECT u.id, o.amount FROM users u JOIN orders o ON u.id = o.user_id');
      expect(target, isNull);
    });

    test('returns null for comma FROM', () {
      expect(
        SqlTableTargetExtractor.extract('SELECT * FROM a, b'),
        isNull,
      );
      expect(
        SqlTableTargetExtractor.extract(
            'SELECT * FROM users u, orders o WHERE u.id = o.user_id'),
        isNull,
      );
    });

    test('returns null for subquery FROM', () {
      expect(
        SqlTableTargetExtractor.extract(
            'SELECT * FROM (SELECT * FROM users) x'),
        isNull,
      );
    });

    test('returns null for VALUES', () {
      expect(SqlTableTargetExtractor.extract('VALUES (1, 2)'), isNull);
      expect(
        SqlTableTargetExtractor.extract('SELECT * FROM (VALUES (1)) v'),
        isNull,
      );
    });

    test('returns null for empty or non-FROM queries', () {
      expect(SqlTableTargetExtractor.extract(''), isNull);
      expect(SqlTableTargetExtractor.extract('SELECT 1 + 1'), isNull);
    });

    test('ignores FROM inside extract() and string literals', () {
      final target = SqlTableTargetExtractor.extract(
        "SELECT extract(epoch FROM created_at), name FROM events WHERE name = 'join'",
      );
      expect(target, const SqlTableTarget(tableName: 'events'));
    });
  });

  group('sqlResultGridSaveEnabled', () {
    test('true for simple SELECT when PK columns are in the result', () {
      expect(
        sqlResultGridSaveEnabled(
          sql: 'SELECT * FROM public.t',
          resultColumns: ['id', 'name'],
          primaryKeys: ['id'],
        ),
        isTrue,
      );
    });

    test('false for JOIN and comma FROM', () {
      expect(
        sqlResultGridSaveEnabled(
          sql: 'SELECT * FROM a JOIN b ON a.id = b.id',
          resultColumns: ['id'],
          primaryKeys: ['id'],
        ),
        isFalse,
      );
      expect(
        sqlResultGridSaveEnabled(
          sql: 'SELECT * FROM a, b',
          resultColumns: ['id'],
          primaryKeys: ['id'],
        ),
        isFalse,
      );
    });

    test('false when PK is missing from the result or empty', () {
      expect(
        sqlResultGridSaveEnabled(
          sql: 'SELECT name FROM public.t',
          resultColumns: ['name'],
          primaryKeys: ['id'],
        ),
        isFalse,
      );
      expect(
        sqlResultGridSaveEnabled(
          sql: 'SELECT * FROM public.t',
          resultColumns: ['id', 'name'],
          primaryKeys: [],
        ),
        isFalse,
      );
    });
  });

  group('SQL-grid DML from extracted target', () {
    test('JOIN and comma FROM do not produce DML', () {
      for (final sql in [
        'SELECT * FROM a JOIN b ON a.id = b.id',
        'SELECT * FROM a, b',
      ]) {
        expect(SqlTableTargetExtractor.extract(sql), isNull);
      }
    });

    test('simple SELECT * FROM public.t uses the PK and column types', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM public.t');
      expect(target, const SqlTableTarget(tableName: 't', schema: 'public'));

      final buffer = DataGridStagingBuffer(
        columns: const ['id', 'zip'],
        rows: const [
          ['1', '01234'],
        ],
      );
      buffer.setCell(0, 1, '00789');

      final plan = buffer.generateMutationPlan(
        dialect: SqlDialect.postgres,
        tableName: target!.tableName,
        schema: target.schema,
        primaryKeys: const ['id'],
        columnDataTypes: const {'id': 'integer', 'zip': 'text'},
      );

      expect(plan.statementCount, 1);
      expect(
        plan.statements.single.sql,
        'UPDATE "public"."t" SET "zip" = \'00789\' WHERE "id" = 1',
      );
      expect(plan.statements.single.sql, isNot(contains('"zip" = \'01234\'')));
    });

    test('simple SELECT * FROM t uses the SQLite PK and column types', () {
      final target = SqlTableTargetExtractor.extract('SELECT * FROM t');
      expect(target, const SqlTableTarget(tableName: 't'));

      final buffer = DataGridStagingBuffer(
        columns: const ['id', 'zip'],
        rows: const [
          ['1', '01234'],
        ],
      );
      buffer.setCell(0, 1, '00789');

      final plan = buffer.generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: target!.tableName,
        primaryKeys: const ['id'],
        columnDataTypes: const {'id': 'INTEGER', 'zip': 'TEXT'},
      );

      expect(plan.statementCount, 1);
      expect(
        plan.statements.single.sql,
        'UPDATE "t" SET "zip" = \'00789\' WHERE "id" = 1',
      );
      expect(plan.toTransactionSql(), startsWith('BEGIN TRANSACTION;'));
      expect(plan.statements.single.sql, isNot(contains('"zip" = \'01234\'')));
    });
  });
}
