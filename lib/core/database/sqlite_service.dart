import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

export 'sqlite_connection_pool.dart'
    show
        SqliteLease,
        SqliteSessionMode,
        SqliteSessionModeReadOnly,
        SqliteConnectionPool;

Future<SqliteConnection> _defaultCreateAndConnect(
  ConnectionRow row, {
  required SqliteSessionMode mode,
}) async {
  final conn = SqliteConnection.fromConnectionRow(
    row,
    readOnly: mode.isReadOnlySession,
  );
  await conn.connect();
  return conn;
}

/// Global SQLite connection pool service (singleton).
class SqliteService {
  SqliteService._()
      : _pool = SqliteConnectionPool(
          createAndConnect: _defaultCreateAndConnect,
          maxEntries: SqliteConnectionPool.defaultMaxEntries,
        );

  static final SqliteService instance = SqliteService._();

  final SqliteConnectionPool _pool;

  static const Duration idleDisposeDelay =
      SqliteConnectionPool.defaultIdleDisposeDelay;

  Future<SqliteLease> acquire(
    ConnectionRow row, {
    SqliteSessionMode mode = SqliteSessionMode.readOnly,
  }) =>
      _pool.acquire(row, mode: mode);

  void interrupt(
    ConnectionRow row, {
    SqliteSessionMode mode = SqliteSessionMode.readOnly,
  }) =>
      _pool.interrupt(row, mode: mode);

  /// Force-closes every session mode for this connection id.
  void interruptAllModes(ConnectionRow row) => _pool.interruptAllModes(row);

  /// Whether the SQL-editor read-write slot has an open transaction.
  Future<bool> hasOpenSqlTransaction(ConnectionRow row) =>
      _pool.hasOpenSqlTransaction(row);

  Future<void> disconnectAll() => _pool.disconnectAll();
}
