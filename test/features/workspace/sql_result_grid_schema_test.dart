import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/database/sql_table_target_extractor.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';
import 'package:querya_desktop/features/workspace/data_grid_staging_buffer.dart';
import 'package:querya_desktop/features/workspace/sql_result_grid_schema.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  const usersSchema = TableSchemaMeta(
    tableName: 'users',
    columns: [
      TableColumnMeta(
        name: 'id',
        dataType: 'integer',
        isNullable: false,
        isPrimaryKey: true,
        hasServerDefault: true,
      ),
      TableColumnMeta(name: 'name', dataType: 'text'),
    ],
    primaryKeys: ['id'],
  );

  group('SqlResultGridSchema.fromLoad', () {
    test('carries primary keys, types and column meta from the schema', () {
      final schema = SqlResultGridSchema.fromLoad(
        const TableViewSchemaLoad.ok(usersSchema),
      );
      expect(schema.primaryKeys, ['id']);
      expect(schema.columnDataTypes, {'id': 'integer', 'name': 'text'});
      expect(schema.columnMeta!['id']!.hasServerDefault, isTrue);
      expect(schema.schemaError, isNull);
      expect(schema.editHint(['id', 'name']), isNull);
    });

    test('a failed schema load is reported, not treated as "no primary key"',
        () {
      final schema = SqlResultGridSchema.fromLoad(
        TableViewSchemaLoad.failed(StateError('permission denied')),
      );
      expect(schema.primaryKeys, isEmpty);
      expect(schema.columnMeta, isNull);
      final hint = schema.editHint(['id']);
      expect(hint, contains('schema unavailable'));
      expect(hint, contains('permission denied'));
    });

    test('SqlResultGridSchema.none has nothing to say', () {
      expect(SqlResultGridSchema.none.editHint(const ['a']), isNull);
      expect(SqlResultGridSchema.none.primaryKeys, isEmpty);
    });

    test('implicit rowid keys a table without a declared primary key', () {
      const noPk = TableSchemaMeta(
        tableName: 't',
        columns: [TableColumnMeta(name: 'name', dataType: 'TEXT')],
      );
      final schema = SqlResultGridSchema.fromLoad(
        const TableViewSchemaLoad.ok(noPk),
        sqliteImplicitRowid: true,
      );
      expect(schema.primaryKeys, [kSqliteImplicitRowid]);
      expect(schema.needsRowidColumn, isTrue);
      expect(schema.columnDataTypes![kSqliteImplicitRowid], 'INTEGER');
      expect(schema.columnMeta!.containsKey(kSqliteImplicitRowid), isTrue);

      expect(schema.editHint(['name']), contains('include rowid'));
      expect(schema.editHint(['rowid', 'name']), isNull);
    });

    test('a declared primary key wins over rowid', () {
      final schema = SqlResultGridSchema.fromLoad(
        const TableViewSchemaLoad.ok(usersSchema),
        sqliteImplicitRowid: true,
      );
      expect(schema.primaryKeys, ['id']);
      expect(schema.needsRowidColumn, isFalse);
      expect(schema.editHint(['name']), isNull);
    });

    test('without the SQLite fallback a keyless table stays read-only', () {
      const noPk = TableSchemaMeta(tableName: 't');
      final schema =
          SqlResultGridSchema.fromLoad(const TableViewSchemaLoad.ok(noPk));
      expect(schema.primaryKeys, isEmpty);
      expect(schema.needsRowidColumn, isFalse);
    });
  });

  test('withEditHint appends the hint as a second sentence', () {
    expect(withEditHint('3 row(s).', null), '3 row(s).');
    expect(withEditHint('3 row(s).', 'Cannot edit.'), '3 row(s). Cannot edit.');
  });

  group('SQL grid Save against a real SQLite table', () {
    late SqliteConnection conn;

    setUp(() async {
      conn = SqliteConnection(
        id: 1,
        name: 'mem',
        path: inMemoryDatabasePath,
        readOnly: false,
      );
      await conn.connect();
    });

    tearDown(() => conn.disconnect());

    Future<SqlResultGridSchema> schemaFor(String table) async =>
        SqlResultGridSchema.fromLoad(
          await loadTableViewSchema(() => conn.getTableSchema(table: table)),
          sqliteImplicitRowid: true,
        );

    test('SELECT rowid, * on a keyless table can be saved, one duplicate row only',
        () async {
      await conn.execute('CREATE TABLE t (name TEXT)');
      await conn.execute("INSERT INTO t (name) VALUES ('dup'), ('dup')");
      const sql = 'SELECT rowid, * FROM t';
      final schema = await schemaFor('t');

      final rs = await conn.execute(sql);
      final cols = rs.first.keys.toList();
      expect(cols, ['rowid', 'name']);
      expect(
        sqlResultGridSaveEnabled(
          sql: sql,
          resultColumns: cols,
          primaryKeys: schema.primaryKeys,
        ),
        isTrue,
      );
      expect(schema.editHint(cols), isNull);

      final buffer = DataGridStagingBuffer(
        columns: cols,
        rows: [
          for (final r in rs) [for (final c in cols) '${r[c]}'],
        ],
        primaryKeys: schema.primaryKeys,
      );
      addTearDown(buffer.dispose);
      buffer.setCell(0, 1, 'changed');
      final plan = buffer.generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: 't',
        primaryKeys: schema.primaryKeys,
        columnDataTypes: schema.columnDataTypes,
        columnMeta: schema.columnMeta,
      );
      expect(plan.statements.single.sql, contains('WHERE "rowid" = 1'));
      expect(await conn.executeAffected(plan.statements.single.sql), 1);
      final after = await conn.execute('SELECT name FROM t ORDER BY rowid');
      expect(after.map((r) => r['name']), ['changed', 'dup']);
    });

    test('SELECT * on a keyless table stays read-only and explains why',
        () async {
      await conn.execute('CREATE TABLE t (name TEXT)');
      const sql = 'SELECT * FROM t';
      final schema = await schemaFor('t');

      expect(
        sqlResultGridSaveEnabled(
          sql: sql,
          resultColumns: const ['name'],
          primaryKeys: schema.primaryKeys,
        ),
        isFalse,
      );
      expect(schema.editHint(const ['name']), contains('include rowid'));
    });

    test('schema meta lets INSERT omit a blank generated key', () async {
      await conn.execute('CREATE TABLE u (id INTEGER PRIMARY KEY, name TEXT)');
      final schema = await schemaFor('u');

      DataGridStagingBuffer inserting() {
        final b = DataGridStagingBuffer(
          columns: const ['id', 'name'],
          rows: const [],
          primaryKeys: schema.primaryKeys,
        )..addRow(['', 'Grace']);
        addTearDown(b.dispose);
        return b;
      }

      final withMeta = inserting().generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: 'u',
        primaryKeys: schema.primaryKeys,
        columnDataTypes: schema.columnDataTypes,
        columnMeta: schema.columnMeta,
      );
      expect(withMeta.statements.single.sql, isNot(contains('"id"')));
      expect(await conn.executeAffected(withMeta.statements.single.sql), 1);

      final withoutMeta = inserting().generateMutationPlan(
        dialect: SqlDialect.sqlite,
        tableName: 'u',
        primaryKeys: schema.primaryKeys,
        columnDataTypes: schema.columnDataTypes,
      );
      expect(withoutMeta.statements.single.sql, contains('"id"'));
    });
  });
}
