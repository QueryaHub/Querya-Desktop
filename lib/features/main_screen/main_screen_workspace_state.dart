import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/mysql/mysql_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';

/// Workspace / tree selection shown in [WorkspacePanel] and [ConnectionsPanel].
@immutable
class MainScreenWorkspaceState {
  const MainScreenWorkspaceState({
    this.activeConnection,
    this.activeRedisDb,
    this.activeMongoDB,
    this.selectedPostgresObject,
    this.postgresSqlTabRequestToken = 0,
    this.selectedMysqlObject,
    this.mysqlSqlTabRequestToken = 0,
  });

  final ConnectionRow? activeConnection;
  final int? activeRedisDb;
  final String? activeMongoDB;
  final ({String database, String schema, String name, PostgresObjectKind kind})?
      selectedPostgresObject;
  final int postgresSqlTabRequestToken;
  final ({String database, String name, MysqlObjectKind kind})?
      selectedMysqlObject;
  final int mysqlSqlTabRequestToken;

  static const empty = MainScreenWorkspaceState();

  MainScreenWorkspaceState selectConnection(ConnectionRow connection) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState selectPostgresObject(
    ConnectionRow connection,
    String database,
    String schema,
    String name,
    PostgresObjectKind kind,
  ) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: (
        database: database,
        schema: schema,
        name: name,
        kind: kind,
      ),
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState selectMysqlObject(
    ConnectionRow connection,
    String database,
    String name,
    MysqlObjectKind kind,
  ) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: (
        database: database,
        name: name,
        kind: kind,
      ),
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState selectRedisDb(ConnectionRow connection, int db) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: db,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState selectMongoDb(
      ConnectionRow connection, String database) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: database,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState openPostgresSqlWorkspace(ConnectionRow connection) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken + 1,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken,
    );
  }

  MainScreenWorkspaceState openMysqlSqlWorkspace(ConnectionRow connection) {
    return MainScreenWorkspaceState(
      activeConnection: connection,
      activeRedisDb: null,
      activeMongoDB: null,
      selectedPostgresObject: null,
      postgresSqlTabRequestToken: postgresSqlTabRequestToken,
      selectedMysqlObject: null,
      mysqlSqlTabRequestToken: mysqlSqlTabRequestToken + 1,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MainScreenWorkspaceState &&
        activeConnection?.id == other.activeConnection?.id &&
        activeRedisDb == other.activeRedisDb &&
        activeMongoDB == other.activeMongoDB &&
        _pgEquals(selectedPostgresObject, other.selectedPostgresObject) &&
        postgresSqlTabRequestToken == other.postgresSqlTabRequestToken &&
        _mysqlEquals(selectedMysqlObject, other.selectedMysqlObject) &&
        mysqlSqlTabRequestToken == other.mysqlSqlTabRequestToken;
  }

  @override
  int get hashCode => Object.hash(
        activeConnection?.id,
        activeRedisDb,
        activeMongoDB,
        selectedPostgresObject == null
            ? 0
            : Object.hash(
                selectedPostgresObject!.database,
                selectedPostgresObject!.schema,
                selectedPostgresObject!.name,
                selectedPostgresObject!.kind,
              ),
        postgresSqlTabRequestToken,
        selectedMysqlObject == null
            ? 0
            : Object.hash(
                selectedMysqlObject!.database,
                selectedMysqlObject!.name,
                selectedMysqlObject!.kind,
              ),
        mysqlSqlTabRequestToken,
      );
}

bool _pgEquals(
  ({String database, String schema, String name, PostgresObjectKind kind})? a,
  ({String database, String schema, String name, PostgresObjectKind kind})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.database == b.database &&
      a.schema == b.schema &&
      a.name == b.name &&
      a.kind == b.kind;
}

bool _mysqlEquals(
  ({String database, String name, MysqlObjectKind kind})? a,
  ({String database, String name, MysqlObjectKind kind})? b,
) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  return a.database == b.database && a.name == b.name && a.kind == b.kind;
}
