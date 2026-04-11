import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/mysql_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

export 'mysql_connection_pool.dart'
    show MysqlLease, MysqlSessionMode, MysqlConnectionPool;

Future<MysqlConnection> _defaultCreateAndConnect(
  ConnectionRow row, {
  required String database,
  required MysqlSessionMode mode,
}) async {
  final conn = MysqlConnection.fromConnectionRow(
    row,
    database: database.isEmpty ? null : database,
  );
  await conn.connect();
  await conn.setSessionReadOnly(mode == MysqlSessionMode.readOnly);
  return conn;
}

/// Global MySQL connection pool (singleton).
class MysqlService {
  MysqlService._()
      : _pool = MysqlConnectionPool(
          createAndConnect: _defaultCreateAndConnect,
          maxEntries: MysqlConnectionPool.defaultMaxEntries,
        );

  static final MysqlService instance = MysqlService._();

  final MysqlConnectionPool _pool;

  static const Duration idleDisposeDelay =
      MysqlConnectionPool.defaultIdleDisposeDelay;

  Future<MysqlLease> acquire(
    ConnectionRow row, {
    required String database,
    MysqlSessionMode mode = MysqlSessionMode.readOnly,
  }) =>
      _pool.acquire(row, database: database, mode: mode);

  void interrupt(
    ConnectionRow row, {
    required String database,
    MysqlSessionMode mode = MysqlSessionMode.readOnly,
  }) =>
      _pool.interrupt(row, database: database, mode: mode);

  Future<void> disconnectAll() => _pool.disconnectAll();
}
