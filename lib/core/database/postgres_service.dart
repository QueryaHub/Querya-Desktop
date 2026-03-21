import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection_pool.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

export 'postgres_connection_pool.dart'
    show PgLease, PgSessionMode, PostgresConnectionPool;

Future<PostgresConnection> _defaultCreateAndConnect(
  ConnectionRow row, {
  required String database,
  required PgSessionMode mode,
}) async {
  final conn = PostgresConnection.fromConnectionRow(row, database: database);
  await conn.connect();
  await conn.setSessionReadOnly(mode == PgSessionMode.readOnly);
  return conn;
}

/// Global PostgreSQL connection pool (singleton).
///
/// For tests of pool logic without a server, use [PostgresConnectionPool]
/// with a fake [PostgresPoolConnectionFactory].
class PostgresService {
  PostgresService._()
      : _pool = PostgresConnectionPool(
          createAndConnect: _defaultCreateAndConnect,
          maxEntries: PostgresConnectionPool.defaultMaxEntries,
        );

  static final PostgresService instance = PostgresService._();

  final PostgresConnectionPool _pool;

  /// Same as [PostgresConnectionPool.defaultIdleDisposeDelay].
  static const Duration idleDisposeDelay =
      PostgresConnectionPool.defaultIdleDisposeDelay;

  /// Obtains a connected [PostgresConnection], incrementing the pool ref-count.
  Future<PgLease> acquire(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) =>
      _pool.acquire(row, database: database, mode: mode);

  /// Force-closes the pooled connection for this key.
  void interrupt(
    ConnectionRow row, {
    required String database,
    PgSessionMode mode = PgSessionMode.readOnly,
  }) =>
      _pool.interrupt(row, database: database, mode: mode);

  /// Closes all pooled connections (e.g. app shutdown).
  Future<void> disconnectAll() => _pool.disconnectAll();
}
