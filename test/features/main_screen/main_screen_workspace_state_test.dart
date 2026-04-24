import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
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
  });
}
