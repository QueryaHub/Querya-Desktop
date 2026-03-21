import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

import 'postgres_metadata.dart';

/// Replaces the database in a `postgresql://` / `postgres://` URI (path or
/// `database=` query param). Used when switching DB while keeping URI auth/SSL.
String replaceDatabaseInConnectionString(
  String connectionString,
  String newDatabase,
) {
  final uri = Uri.parse(connectionString.trim());
  if (uri.scheme != 'postgres' && uri.scheme != 'postgresql') {
    throw ArgumentError(
      'Invalid connection string scheme: ${uri.scheme}. '
      'Expected "postgresql" or "postgres".',
    );
  }
  final params = Map<String, String>.from(uri.queryParameters);
  if (params.containsKey('database')) {
    params['database'] = newDatabase;
    return uri.replace(queryParameters: params).toString();
  }
  if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
    return uri.replace(path: '/$newDatabase').toString();
  }
  params['database'] = newDatabase;
  return uri.replace(queryParameters: params).toString();
}

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

  /// Builds a connection from a saved [ConnectionRow] (host/port or URI).
  factory PostgresConnection.fromConnectionRow(
    ConnectionRow row, {
    String? database,
  }) {
    return PostgresConnection(
      id: row.id ?? 0,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 5432,
      username: row.username,
      password: row.password,
      database: database ?? row.databaseName ?? 'postgres',
      useSSL: row.useSSL,
      connectionString: row.connectionString,
    );
  }

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

  bool get _usesConnectionString =>
      connectionString != null && connectionString!.trim().isNotEmpty;

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
      if (_usesConnectionString) {
        _conn = await Connection.openFromUrl(connectionString!.trim());
      } else {
        _conn = await Connection.open(
          _buildEndpoint(),
          settings: _buildSettings(),
        );
      }
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

  /// Drops the TCP session immediately (kills pending client I/O). Used when
  /// cancelling a long query or [PostgresService.interrupt].
  Future<void> forceClose() async {
    _isConnected = false;
    final c = _conn;
    _conn = null;
    try {
      await c?.close(force: true);
    } catch (_) {}
  }

  /// Session-level default for transactions (browse vs SQL editor).
  Future<void> setSessionReadOnly(bool readOnly) async {
    if (!isConnected) return;
    await execute(
      readOnly
          ? 'SET default_transaction_read_only = ON'
          : 'SET default_transaction_read_only = OFF',
    );
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

  /// Connect to a specific database (creates a new connection config).
  Future<PostgresConnection> connectToDatabase(String dbName) async {
    final cs = connectionString;
    final newCs = (cs != null && cs.trim().isNotEmpty)
        ? replaceDatabaseInConnectionString(cs, dbName)
        : null;
    return PostgresConnection(
      id: id,
      name: name,
      host: host,
      port: port,
      username: username,
      password: password,
      database: dbName,
      useSSL: useSSL,
      connectionString: newCs,
    );
  }

  /// All overloads of a function in [schema] named [name] ([pg_get_functiondef]).
  Future<List<PgFunctionOverload>> getFunctionDefinitions(
    String schema,
    String name,
  ) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT p.oid::regprocedure::text AS signature,
       pg_get_functiondef(p.oid)::text AS definition
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = @schema AND p.proname = @name
ORDER BY p.oid
''',
      ),
      parameters: {'schema': schema, 'name': name},
    );
    return result
        .map(
          (row) => PgFunctionOverload(
            signature: row[0] as String,
            definition: row[1] as String,
          ),
        )
        .toList();
  }

  /// Metadata and approximate DDL for a sequence (requires PG 10+ [pg_sequences]).
  Future<PostgresSequenceDetails?> getSequenceDetails(
    String schema,
    String name,
  ) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT last_value::text, start_value::text, min_value::text, max_value::text,
       increment_by::text, cycle, cache_size::text,
       schemaname::text, sequencename::text
FROM pg_sequences
WHERE schemaname = @schema AND sequencename = @name
''',
      ),
      parameters: {'schema': schema, 'name': name},
    );
    if (result.isEmpty) return null;
    final row = result.first;
    final sc = row[7] as String;
    final seq = row[8] as String;
    final cycle = _parsePgBool(row[5]);
    final ddl = _buildSequenceDdl(
      schema: sc,
      name: seq,
      incrementBy: row[4] as String,
      minValue: row[2] as String,
      maxValue: row[3] as String,
      startValue: row[1] as String,
      cacheSize: row[6] as String,
      cycle: cycle,
    );
    return PostgresSequenceDetails(
      schema: sc,
      name: seq,
      lastValue: row[0] as String,
      startValue: row[1] as String,
      minValue: row[2] as String,
      maxValue: row[3] as String,
      incrementBy: row[4] as String,
      cacheSize: row[6] as String,
      cycle: cycle,
      ddl: ddl,
    );
  }

  Future<List<String>> listMaterializedViews({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        'SELECT matviewname FROM pg_matviews WHERE schemaname = @schema '
        'ORDER BY matviewname',
      ),
      parameters: {'schema': schema},
    );
    return result.map((row) => row[0] as String).toList();
  }

  Future<void> refreshMaterializedView(String schema, String name) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final q = '${_quoteIdent(schema)}.${_quoteIdent(name)}';
    await _conn!.execute('REFRESH MATERIALIZED VIEW $q');
  }

  Future<List<PgIndexRow>> listIndexesInSchema(String schema) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT c.relname::text,
       i.relname::text,
       COALESCE(pg_relation_size(i.oid), 0)::bigint,
       pg_get_indexdef(i.oid)::text
FROM pg_index x
JOIN pg_class c ON c.oid = x.indrelid
JOIN pg_class i ON i.oid = x.indexrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = @schema
  AND c.relkind IN ('r', 'm', 'p')
ORDER BY c.relname, i.relname
''',
      ),
      parameters: {'schema': schema},
    );
    return result
        .map(
          (row) => PgIndexRow(
            tableName: row[0] as String,
            indexName: row[1] as String,
            indexDef: row[3] as String,
            sizeBytes: _parseSize(row[2]),
          ),
        )
        .toList();
  }

  static int? _parseSize(Object? v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is BigInt) return v.toInt();
    return int.tryParse(v.toString());
  }

  Future<List<PgTriggerRow>> listTriggersInSchema(String schema) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT c.relname::text,
       t.tgname::text,
       pg_get_triggerdef(t.oid)::text
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = @schema
  AND NOT t.tgisinternal
ORDER BY c.relname, t.tgname
''',
      ),
      parameters: {'schema': schema},
    );
    return result
        .map(
          (row) => PgTriggerRow(
            tableName: row[0] as String,
            triggerName: row[1] as String,
            definition: row[2] as String,
          ),
        )
        .toList();
  }

  Future<List<PgTypeRow>> listUserTypesInSchema(String schema) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT t.typname::text,
       CASE t.typtype
         WHEN 'b' THEN 'base'
         WHEN 'c' THEN 'composite'
         WHEN 'd' THEN 'domain'
         WHEN 'e' THEN 'enum'
         WHEN 'p' THEN 'pseudo'
         WHEN 'r' THEN 'range'
         WHEN 'm' THEN 'multirange'
         ELSE t.typtype::text
       END
FROM pg_type t
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = @schema
  AND t.typtype IN ('c', 'd', 'e', 'r', 'm')
ORDER BY t.typname
''',
      ),
      parameters: {'schema': schema},
    );
    return result
        .map(
          (row) => PgTypeRow(
            name: row[0] as String,
            kind: row[1] as String,
          ),
        )
        .toList();
  }

  Future<List<PgExtensionRow>> listExtensions() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      'SELECT extname::text, extversion::text FROM pg_extension ORDER BY extname',
    );
    return result
        .map(
          (row) => PgExtensionRow(
            name: row[0] as String,
            version: row[1] as String,
          ),
        )
        .toList();
  }

  Future<List<PgFdwRow>> listForeignDataWrappers() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      r'''
SELECT fdwname::text, fdwhandler::regproc::text
FROM pg_foreign_data_wrapper
ORDER BY fdwname
''',
    );
    return result
        .map(
          (row) => PgFdwRow(
            name: row[0] as String,
            handler: row[1] as String?,
          ),
        )
        .toList();
  }

  Future<List<PgForeignServerRow>> listForeignServers() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      r'''
SELECT s.srvname::text, w.fdwname::text
FROM pg_foreign_server s
JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
ORDER BY s.srvname
''',
    );
    return result
        .map(
          (row) => PgForeignServerRow(
            serverName: row[0] as String,
            fdwName: row[1] as String,
          ),
        )
        .toList();
  }

  Future<List<PgTablePrivilegeRow>> listTablePrivileges(
    String schema,
    String table,
  ) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _conn!.execute(
      Sql.named(
        r'''
SELECT grantee::text, privilege_type::text, is_grantable::text
FROM information_schema.role_table_grants
WHERE table_schema = @schema AND table_name = @table
ORDER BY grantee, privilege_type
''',
      ),
      parameters: {'schema': schema, 'table': table},
    );
    return result
        .map(
          (row) => PgTablePrivilegeRow(
            grantee: row[0] as String,
            privilegeType: row[1] as String,
            isGrantable: row[2] as String,
          ),
        )
        .toList();
  }

  static String _quoteIdent(String id) =>
      '"${id.replaceAll('"', '""')}"';

  static bool _parsePgBool(Object? v) {
    if (v is bool) return v;
    final s = v?.toString().toLowerCase() ?? '';
    return s == 't' || s == 'true';
  }

  static String _buildSequenceDdl({
    required String schema,
    required String name,
    required String incrementBy,
    required String minValue,
    required String maxValue,
    required String startValue,
    required String cacheSize,
    required bool cycle,
  }) {
    final qSchema = _quoteIdent(schema);
    final qName = _quoteIdent(name);
    return 'CREATE SEQUENCE $qSchema.$qName\n'
        '  INCREMENT BY $incrementBy\n'
        '  MINVALUE $minValue\n'
        '  MAXVALUE $maxValue\n'
        '  START $startValue\n'
        '  CACHE $cacheSize\n'
        '  ${cycle ? 'CYCLE' : 'NO CYCLE'};';
  }
}

/// One overload returned by [PostgresConnection.getFunctionDefinitions].
class PgFunctionOverload {
  const PgFunctionOverload({
    required this.signature,
    required this.definition,
  });

  final String signature;
  final String definition;
}

/// Row from [pg_sequences] plus generated DDL.
class PostgresSequenceDetails {
  const PostgresSequenceDetails({
    required this.schema,
    required this.name,
    required this.lastValue,
    required this.startValue,
    required this.minValue,
    required this.maxValue,
    required this.incrementBy,
    required this.cacheSize,
    required this.cycle,
    required this.ddl,
  });

  final String schema;
  final String name;
  final String lastValue;
  final String startValue;
  final String minValue;
  final String maxValue;
  final String incrementBy;
  final String cacheSize;
  final bool cycle;
  final String ddl;
}

class PostgresConnectionException implements Exception {
  PostgresConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}
