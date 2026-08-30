import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connections_panel.dart'
    show SqliteObjectKind;
import 'package:querya_desktop/features/main_screen/main_screen_workspace_state.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';

void main() {
  final createdAt = DateTime.utc(2025).toIso8601String();
  final pgConn = ConnectionRow(
    type: 'postgresql',
    name: 'pg',
    host: '127.0.0.1',
    port: 5432,
    createdAt: createdAt,
    id: 10,
  );
  final mysqlConn = ConnectionRow(
    type: 'mysql',
    name: 'my',
    host: '127.0.0.1',
    port: 3306,
    createdAt: createdAt,
    id: 11,
  );
  final sqliteConn = ConnectionRow(
    type: 'sqlite',
    name: 'lite',
    databaseName: '/tmp/test.db',
    createdAt: createdAt,
    id: 12,
  );
  final clickhouseConn = ConnectionRow(
    type: 'clickhouse',
    name: 'ch',
    host: '127.0.0.1',
    port: 8123,
    createdAt: createdAt,
    id: 13,
  );

  group('MainScreenWorkspaceState', () {
    test('empty has no selection', () {
      expect(MainScreenWorkspaceState.empty.activeConnection, isNull);
      expect(MainScreenWorkspaceState.empty.selectedPostgresObject, isNull);
      expect(MainScreenWorkspaceState.empty.selectedMysqlObject, isNull);
    });

    test('selectConnection clears db-specific selection', () {
      final withPg = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'db',
        'public',
        't1',
        PostgresObjectKind.table,
      );
      final next = withPg.selectConnection(mysqlConn);
      expect(next.activeConnection?.id, 11);
      expect(next.selectedPostgresObject, isNull);
      expect(next.postgresSqlEditorContext, isNull);
      expect(next.postgresSqlEditorContextToken, 0);
      expect(next.activeRedisDb, isNull);
      expect(next.activeMongoDB, isNull);
    });

    test('selectPostgresObject keeps connection and pg tuple', () {
      final s = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'app',
        'public',
        'users',
        PostgresObjectKind.table,
      );
      expect(s.activeConnection?.id, 10);
      expect(s.selectedPostgresObject?.name, 'users');
      expect(s.selectedPostgresObject?.kind, PostgresObjectKind.table);
      expect(s.postgresSqlEditorContext, isNull);
      expect(s.postgresSqlEditorContextToken, 0);
    });

    test('openPostgresSqlWorkspace bumps token and clears selection', () {
      final withObj = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'db',
        's',
        'fn',
        PostgresObjectKind.function,
      );
      final sql = withObj.openPostgresSqlWorkspace(pgConn);
      expect(sql.postgresSqlTabRequestToken, 1);
      expect(sql.selectedPostgresObject, isNull);
      expect(sql.postgresSqlEditorContext, isNull);
      expect(sql.postgresSqlEditorContextToken, 0);
    });

    test('openPostgresSqlWorkspace seeds editor from selected table/view', () {
      final withTable = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'warehouse',
        'public',
        'stock',
        PostgresObjectKind.table,
      );
      final sql = withTable.openPostgresSqlWorkspace(pgConn);
      expect(sql.postgresSqlTabRequestToken, 1);
      expect(sql.selectedPostgresObject, isNull);
      expect(sql.postgresSqlEditorContext?.database, 'warehouse');
      expect(sql.postgresSqlEditorContext?.name, 'stock');
      expect(sql.postgresSqlEditorContextToken, 1);
    });

    test('openPostgresSqlWorkspace explicit seed overrides workspace selection',
        () {
      final withBatches = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'postgres',
        'public',
        'batches',
        PostgresObjectKind.table,
      );
      final sql = withBatches.openPostgresSqlWorkspace(
        pgConn,
        seedDatabase: 'postgres',
        seedSchema: 'public',
        seedName: 'stock',
        seedKind: PostgresObjectKind.table,
      );
      expect(sql.postgresSqlEditorContext?.name, 'stock');
      expect(sql.postgresSqlTabRequestToken, 1);
    });

    test('openPostgresSqlWorkspace does not seed for another connection id',
        () {
      final otherPg = ConnectionRow(
        type: 'postgresql',
        name: 'pg2',
        host: '127.0.0.1',
        port: 5432,
        createdAt: createdAt,
        id: 99,
      );
      final withTable = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'warehouse',
        'public',
        'stock',
        PostgresObjectKind.table,
      );
      final sql = withTable.openPostgresSqlWorkspace(otherPg);
      expect(sql.postgresSqlEditorContext, isNull);
      expect(sql.postgresSqlEditorContextToken, 0);
    });

    test('selectRedisDb and selectMongoDb are mutually exclusive fields', () {
      final redis = MainScreenWorkspaceState.empty.selectRedisDb(pgConn, 3);
      expect(redis.activeRedisDb, 3);
      expect(redis.activeMongoDB, isNull);
      final mongo = redis.selectMongoDb(pgConn, 'inventory');
      expect(mongo.activeMongoDB, 'inventory');
      expect(mongo.activeRedisDb, isNull);
    });

    test('equality uses connection id and selections', () {
      final a = MainScreenWorkspaceState.empty.selectMysqlObject(
        mysqlConn,
        'db1',
        'orders',
        MysqlObjectKind.table,
      );
      final b = MainScreenWorkspaceState.empty.selectMysqlObject(
        mysqlConn,
        'db1',
        'orders',
        MysqlObjectKind.table,
      );
      expect(a, b);
      final c = MainScreenWorkspaceState.empty.selectMysqlObject(
        mysqlConn,
        'db1',
        'other',
        MysqlObjectKind.table,
      );
      expect(a, isNot(c));
    });

    test('read-only state toggle and reset', () {
      var state = MainScreenWorkspaceState.empty;
      expect(state.isReadOnly, isFalse);

      state = state.toggleReadOnly();
      expect(state.isReadOnly, isTrue);

      state = state.toggleReadOnly();
      expect(state.isReadOnly, isFalse);

      state = state.toggleReadOnly();
      expect(state.isReadOnly, isTrue);

      // Selecting a new connection should reset isReadOnly to false
      state = state.selectConnection(mysqlConn);
      expect(state.isReadOnly, isFalse);
    });

    test('unselectActiveObject and restoreLastSelectedObject for fluid return',
        () {
      final withTable = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'warehouse',
        'public',
        'stock',
        PostgresObjectKind.table,
      );
      expect(withTable.selectedPostgresObject?.name, 'stock');
      expect(withTable.lastSelectedPostgresObject?.name, 'stock');

      final unselected = withTable.unselectActiveObject();
      expect(unselected.selectedPostgresObject, isNull);
      expect(unselected.lastSelectedPostgresObject?.name, 'stock');

      final restored = unselected.restoreLastSelectedObject();
      expect(restored.selectedPostgresObject?.name, 'stock');
      expect(restored.selectedPostgresObject?.schema, 'public');

      // Selecting the same connection keeps lastSelected
      final reselectedSame = withTable.selectConnection(pgConn);
      expect(reselectedSame.selectedPostgresObject, isNull);
      expect(reselectedSame.lastSelectedPostgresObject?.name, 'stock');

      // Selecting a different connection clears lastSelected
      final diffConn = reselectedSame.selectConnection(mysqlConn);
      expect(diffConn.lastSelectedPostgresObject, isNull);
    });

    test('restoreLastSelectedObject is connection-type-aware', () {
      // 1. MySQL connection
      final mysqlState = MainScreenWorkspaceState.empty
          .selectMysqlObject(mysqlConn, 'app_db', 'users', MysqlObjectKind.table)
          .unselectActiveObject();
      expect(mysqlState.selectedMysqlObject, isNull);
      expect(mysqlState.lastSelectedMysqlObject?.name, 'users');
      final restoredMy = mysqlState.restoreLastSelectedObject();
      expect(restoredMy.selectedMysqlObject?.name, 'users');
      expect(restoredMy.selectedPostgresObject, isNull);

      // 2. SQLite connection
      final sqliteState = MainScreenWorkspaceState.empty
          .selectSqliteObject(sqliteConn, 'settings', SqliteObjectKind.table)
          .unselectActiveObject();
      expect(sqliteState.selectedSqliteObject, isNull);
      expect(sqliteState.lastSelectedSqliteObject?.name, 'settings');
      final restoredSq = sqliteState.restoreLastSelectedObject();
      expect(restoredSq.selectedSqliteObject?.name, 'settings');

      // 3. Extension (ClickHouse) connection
      final extState = MainScreenWorkspaceState.empty
          .selectExtensionObject(clickhouseConn, 'analytics', 'hits')
          .unselectActiveObject();
      expect(extState.selectedExtensionObject, isNull);
      expect(extState.lastSelectedExtensionObject?.name, 'hits');
      final restoredExt = extState.restoreLastSelectedObject();
      expect(restoredExt.selectedExtensionObject?.name, 'hits');
    });

    test('restoreLastSelectedObject ignores cached references from other drivers', () {
      // Craft a state where active connection is MySQL but lastSelectedPostgresObject is non-null
      const mismatchedState = MainScreenWorkspaceState(
        activeConnection: ConnectionRow(
          type: 'mysql',
          name: 'my_db',
          createdAt: '2025-01-01',
          id: 50,
        ),
        lastSelectedPostgresObject: (
          database: 'pg_db',
          schema: 'public',
          name: 'pg_table',
          kind: PostgresObjectKind.table,
        ),
      );

      final restored = mismatchedState.restoreLastSelectedObject();
      // Must NOT invoke selectPostgresObject with a MySQL connection
      expect(restored.selectedPostgresObject, isNull);
      expect(restored.selectedMysqlObject, isNull);
    });

    test('select*Object clears cached object references of other drivers', () {
      final statePg = MainScreenWorkspaceState.empty.selectPostgresObject(
        pgConn,
        'db',
        'public',
        't1',
        PostgresObjectKind.table,
      );
      expect(statePg.lastSelectedPostgresObject?.name, 't1');
      expect(statePg.lastSelectedMysqlObject, isNull);
      expect(statePg.lastSelectedSqliteObject, isNull);
      expect(statePg.lastSelectedExtensionObject, isNull);

      final stateMy = statePg.selectMysqlObject(
        mysqlConn,
        'db',
        't2',
        MysqlObjectKind.table,
      );
      expect(stateMy.lastSelectedPostgresObject, isNull);
      expect(stateMy.lastSelectedMysqlObject?.name, 't2');
      expect(stateMy.lastSelectedSqliteObject, isNull);
      expect(stateMy.lastSelectedExtensionObject, isNull);

      final stateSq = stateMy.selectSqliteObject(
        sqliteConn,
        't3',
        SqliteObjectKind.table,
      );
      expect(stateSq.lastSelectedPostgresObject, isNull);
      expect(stateSq.lastSelectedMysqlObject, isNull);
      expect(stateSq.lastSelectedSqliteObject?.name, 't3');
      expect(stateSq.lastSelectedExtensionObject, isNull);

      final stateExt = stateSq.selectExtensionObject(
        clickhouseConn,
        'db',
        't4',
      );
      expect(stateExt.lastSelectedPostgresObject, isNull);
      expect(stateExt.lastSelectedMysqlObject, isNull);
      expect(stateExt.lastSelectedSqliteObject, isNull);
      expect(stateExt.lastSelectedExtensionObject?.name, 't4');
    });
  });
}
