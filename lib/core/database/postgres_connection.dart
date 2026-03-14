import 'package:postgres/postgres.dart';

/// PostgreSQL connection using the pure-Dart `postgres` package.
class PostgresConnection {
  PostgresConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 5432,
    this.username,
    this.password,
    this.database,
    this.useSSL = false,
    this.connectionString,
  });

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  final String? password;
  final String? database;
  final bool useSSL;
  final String? connectionString;

  Connection? _conn;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _conn != null;

  Endpoint _buildEndpoint() {
    return Endpoint(
      host: host,
      port: port,
      database: database ?? 'postgres',
      username: username,
      password: password,
    );
  }

  ConnectionSettings _buildSettings() {
    return ConnectionSettings(
      sslMode: useSSL ? SslMode.require : SslMode.disable,
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 30),
    );
  }

  Future<void> connect() async {
    if (_isConnected && _conn != null) return;
    try {
      _conn = await Connection.open(
        _buildEndpoint(),
        settings: _buildSettings(),
      );
      _isConnected = true;
    } catch (e) {
      _isConnected = false;
      _conn = null;
      rethrow;
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    final c = _conn;
    _conn = null;
    try {
      await c?.close();
    } catch (_) {}
  }

  Future<bool> testConnection() async {
    try {
      await connect();
      if (_conn != null) {
        await _conn!.execute('SELECT 1');
        return true;
      }
      return false;
    } catch (_) {
      return false;
    } finally {
      await disconnect();
    }
  }

  Future<Result> execute(String sql) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    return _conn!.execute(sql);
  }

  Future<List<String>> listDatabases() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listSchemas() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      "SELECT schema_name FROM information_schema.schemata "
      "WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') "
      "ORDER BY schema_name",
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listTables({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = @schema AND table_type = 'BASE TABLE' "
        "ORDER BY table_name",
      ),
      parameters: {'schema': schema},
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listViews({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        "SELECT table_name FROM information_schema.views "
        "WHERE table_schema = @schema "
        "ORDER BY table_name",
      ),
      parameters: {'schema': schema},
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listFunctions({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        "SELECT routine_name FROM information_schema.routines "
        "WHERE routine_schema = @schema AND routine_type = 'FUNCTION' "
        "ORDER BY routine_name",
      ),
      parameters: {'schema': schema},
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listSequences({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        "SELECT sequence_name FROM information_schema.sequences "
        "WHERE sequence_schema = @schema "
        "ORDER BY sequence_name",
      ),
      parameters: {'schema': schema},
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<String> serverVersion() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute('SELECT version()');
    return result.first[0] as String;
  }

  /// Fetches key server statistics for the stats dashboard.
  Future<Map<String, dynamic>> serverStats() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final stats = <String, dynamic>{};

    final ver = await _conn!.execute('SELECT version()');
    stats['version'] = ver.first[0] as String;

    final settings = await _conn!.execute(
      "SELECT name, setting FROM pg_settings "
      "WHERE name IN ('max_connections','shared_buffers','work_mem',"
      "'effective_cache_size','server_version','data_directory',"
      "'listen_addresses','port','server_encoding','timezone')",
    );
    final settingsMap = <String, String>{};
    for (final row in settings) {
      settingsMap[row[0] as String] = row[1] as String;
    }
    stats['settings'] = settingsMap;

    final activity = await _conn!.execute(
      "SELECT count(*) AS total, "
      "count(*) FILTER (WHERE state = 'active') AS active, "
      "count(*) FILTER (WHERE state = 'idle') AS idle "
      "FROM pg_stat_activity",
    );
    if (activity.isNotEmpty) {
      stats['connections_total'] = activity.first[0];
      stats['connections_active'] = activity.first[1];
      stats['connections_idle'] = activity.first[2];
    }

    final dbStats = await _conn!.execute(
      "SELECT datname, pg_database_size(datname) AS size, "
      "numbackends, xact_commit, xact_rollback, blks_read, blks_hit, "
      "tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted "
      "FROM pg_stat_database WHERE datname NOT LIKE 'template%' "
      "ORDER BY datname",
    );
    final dbList = <Map<String, dynamic>>[];
    for (final row in dbStats) {
      dbList.add({
        'datname': row[0],
        'size': row[1],
        'numbackends': row[2],
        'xact_commit': row[3],
        'xact_rollback': row[4],
        'blks_read': row[5],
        'blks_hit': row[6],
        'tup_returned': row[7],
        'tup_fetched': row[8],
        'tup_inserted': row[9],
        'tup_updated': row[10],
        'tup_deleted': row[11],
      });
    }
    stats['databases'] = dbList;

    try {
      final uptime = await _conn!.execute(
        "SELECT extract(epoch from (now() - pg_postmaster_start_time()))::bigint",
      );
      stats['uptime_seconds'] = uptime.first[0];
    } catch (_) {}

    try {
      final dbSize = await _conn!.execute(
        "SELECT pg_database_size(current_database())",
      );
      stats['current_db_size'] = dbSize.first[0];
    } catch (_) {}

    return stats;
  }

  /// Connect to a specific database (creates a new connection).
  Future<PostgresConnection> connectToDatabase(String dbName) async {
    return PostgresConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
      database: dbName,
      useSSL: useSSL,
    );
  }
}

class PostgresConnectionException implements Exception {
  PostgresConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
