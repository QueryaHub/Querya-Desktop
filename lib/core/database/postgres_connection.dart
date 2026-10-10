import 'dart:async';
import 'dart:io' show SecurityContext;

import 'package:flutter/foundation.dart';
import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/database/statement_queue.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_manager.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

// ignore: implementation_imports
import 'package:postgres/src/connection_string.dart' show parseConnectionString;

import 'postgres_metadata.dart';
import 'postgres_result_cells.dart';
import 'postgres_sql.dart';
import 'table_schema_meta.dart';

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

/// Host/port TLS mode when the URI has no `sslmode`.
///
/// [uriSslMode] wins (URI is source of truth). Otherwise encrypt-only
/// (`require`) unless a Root CA is set, then `verifyFull`. `require` does not
/// check the CA — MITM is possible.
SslMode postgresResolveSslMode({
  SslMode? uriSslMode,
  required bool encrypt,
  required bool hasRootCert,
}) {
  if (uriSslMode != null) return uriSslMode;
  if (!encrypt && !hasRootCert) return SslMode.disable;
  if (hasRootCert) return SslMode.verifyFull;
  return SslMode.require;
}

/// `pg_class.reltuples` → row estimate. Negative / unanalyzed → `null`.
int? postgresReltuplesEstimate(Object? value) {
  if (value == null) return null;
  final n = value is num ? value.toDouble() : double.tryParse(value.toString());
  if (n == null || n < 0) return null;
  return n.round();
}

/// PostgreSQL connection using the pure-Dart `postgres` package.
class PostgresConnection {
  PostgresConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 5432,
    this.username,
    String? password,
    this.database,
    this.useSSL = false,
    String? connectionString,
    this.sslRootCert,
    this.sslCert,
    this.sslKey,
    this.sshConfig,
    this.sshSecrets,
  })  : _password = password,
        _connectionString = connectionString;

  /// Builds a connection from a saved [ConnectionRow] (host/port or URI).
  factory PostgresConnection.fromConnectionRow(
    ConnectionRow row, {
    String? database,
  }) {
    String? rootCert;
    String? clientCert;
    String? clientKey;
    if (row.connectionString != null &&
        row.connectionString!.trim().isNotEmpty) {
      final uri = Uri.tryParse(row.connectionString!.trim());
      if (uri != null) {
        rootCert = uri.queryParameters['sslrootcert'];
        clientCert = uri.queryParameters['sslcert'];
        clientKey = uri.queryParameters['sslkey'];
      }
    }
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
      sslRootCert: rootCert,
      sslCert: clientCert,
      sslKey: clientKey,
      sshConfig: row.sshTunnelConfig,
    );
  }

  final int id;
  final String name;
  final String host;
  final int port;
  final String? username;
  String? _password;
  final String? database;
  final bool useSSL;
  String? _connectionString;
  final String? sslRootCert;
  final String? sslCert;
  final String? sslKey;

  final SshTunnelConfig? sshConfig;
  final SshTunnelSecrets? sshSecrets;
  SshTunnelHandle? _sshTunnelHandle;

  SshTunnelHandle? get sshTunnelHandle => _sshTunnelHandle;

  String? get password => _password;
  String? get connectionString => _connectionString;

  Connection? _conn;
  Future<void>? _connecting;

  /// Statements on this session run one at a time, here and not in the
  /// driver: a statement's timeout starts when it starts, and waiting for the
  /// one before it has its own limit (#1216).
  @visibleForTesting
  final statementQueue = StatementQueue();

  /// Test seam: replaces the driver call of [execute].
  @visibleForTesting
  Future<Result> Function(String sql, Duration? timeout)? runStatementForTest;

  bool _isConnected = false;
  bool _inTransaction = false;

  bool get isConnected => _isConnected && _conn != null;

  /// Scrubs sensitive in-memory credentials once the network handshake completes.
  void scrubCredentials() {
    _password = null;
    _connectionString = null;
  }

  bool _usesConnectionString(String? connStr) =>
      connStr != null && connStr.trim().isNotEmpty;

  Endpoint _buildEndpoint({
    String? pass,
    String? hostOverride,
    int? portOverride,
  }) {
    return Endpoint(
      host: hostOverride ?? host,
      port: portOverride ?? port,
      database: database ?? 'postgres',
      username: username,
      password: pass ?? _password,
    );
  }

  ConnectionSettings _buildSettings() {
    SecurityContext? securityContext;
    if ((sslRootCert != null && sslRootCert!.trim().isNotEmpty) ||
        (sslCert != null && sslCert!.trim().isNotEmpty) ||
        (sslKey != null && sslKey!.trim().isNotEmpty)) {
      securityContext = SecurityContext(withTrustedRoots: true);
      if (sslCert != null && sslCert!.trim().isNotEmpty) {
        securityContext.useCertificateChain(sslCert!.trim());
      }
      if (sslKey != null && sslKey!.trim().isNotEmpty) {
        securityContext.usePrivateKey(sslKey!.trim());
      }
      if (sslRootCert != null && sslRootCert!.trim().isNotEmpty) {
        securityContext.setTrustedCertificates(sslRootCert!.trim());
      }
    }
    return ConnectionSettings(
      sslMode: postgresResolveSslMode(
        encrypt: useSSL || securityContext != null,
        hasRootCert: sslRootCert != null && sslRootCert!.trim().isNotEmpty,
      ),
      connectTimeout: const Duration(seconds: 10),
      queryTimeout: const Duration(seconds: 30),
      securityContext: securityContext,
    );
  }

  /// [openFromUrl] already parses `sslmode`, `connect_timeout`, `query_timeout`
  /// from the URI. If `sslmode` is omitted, we fall back to [useSSL] so the
  /// form checkbox still applies; otherwise libpq-style URLs drive TLS mode.
  /// Single-flight: a caller that arrives while an attempt is in progress waits
  /// for that attempt. Without this, two callers opened two sockets and two SSH
  /// tunnels, and a failing attempt dropped the session the other one had made.
  Future<void> connect() {
    if (_isConnected && _conn != null) return Future<void>.value();
    final inFlight = _connecting;
    if (inFlight != null) return inFlight;
    final attempt = _connectOnce();
    _connecting = attempt;
    return attempt.whenComplete(() {
      if (identical(_connecting, attempt)) _connecting = null;
    });
  }

  Future<void> _connectOnce() async {
    if (_isConnected && _conn != null) return;

    var effectivePassword = _password;
    var effectiveConnectionString = _connectionString;

    if ((effectivePassword == null || effectivePassword.isEmpty) &&
        (effectiveConnectionString == null || effectiveConnectionString.isEmpty) &&
        id > 0) {
      // A store that cannot be read throws (#1303): connecting with no password
      // would be reported as a wrong one.
      final secrets = await ConnectionSecretsStore.readForConnection(id);
      effectivePassword = secrets.password;
      effectiveConnectionString = secrets.connectionString;
    }

    try {
      if (sshConfig != null && sshConfig!.enabled) {
        var sec = sshSecrets;
        if (sec == null && id > 0) {
          final stored =
              await ConnectionSecretsStore.readSshSecretsForConnection(id);
          sec = SshTunnelSecrets(
            password: stored.password,
            privateKey: stored.privateKey,
            passphrase: stored.passphrase,
            jumpPassword: stored.jumpPassword,
          );
        }
        _sshTunnelHandle = await SshTunnelManager.instance.openTunnel(
          config: sshConfig!,
          secrets: sec ?? SshTunnelSecrets(),
          remoteHost: host,
          remotePort: port,
        );
      }

      if (_usesConnectionString(effectiveConnectionString)) {
        // Pool passes target catalog via [database]; URI alone would always open
        // the DB embedded in the string — every tree branch then queried the
        // same database (duplicate tables under finance / logistics, etc.).
        final dbName = database ?? 'postgres';
        final uriForOpen = replaceDatabaseInConnectionString(
          effectiveConnectionString!.trim(),
          dbName,
        );
        final parsed = parseConnectionString(uriForOpen);
        final sslMode = postgresResolveSslMode(
          uriSslMode: parsed.sslMode,
          encrypt: useSSL ||
              (sslRootCert != null && sslRootCert!.trim().isNotEmpty) ||
              (sslCert != null && sslCert!.trim().isNotEmpty) ||
              (sslKey != null && sslKey!.trim().isNotEmpty),
          hasRootCert: sslRootCert != null && sslRootCert!.trim().isNotEmpty,
        );
        final endpoint = _sshTunnelHandle != null
            ? Endpoint(
                host: _sshTunnelHandle!.localHost,
                port: _sshTunnelHandle!.localPort,
                database: parsed.endpoints.first.database,
                username: parsed.endpoints.first.username,
                password: parsed.endpoints.first.password,
              )
            : parsed.endpoints.first;
        _conn = await Connection.open(
          endpoint,
          settings: ConnectionSettings(
            applicationName: parsed.applicationName,
            connectTimeout:
                parsed.connectTimeout ?? const Duration(seconds: 10),
            encoding: parsed.encoding,
            replicationMode: parsed.replicationMode,
            queryTimeout: parsed.queryTimeout ?? const Duration(seconds: 30),
            securityContext: parsed.securityContext ?? _buildSettings().securityContext,
            sslMode: sslMode,
          ),
        );
      } else {
        _conn = await Connection.open(
          _buildEndpoint(
            pass: effectivePassword,
            hostOverride: _sshTunnelHandle?.localHost,
            portOverride: _sshTunnelHandle?.localPort,
          ),
          settings: _buildSettings(),
        );
      }
      _isConnected = true;
      _inTransaction = false;
      scrubCredentials();
    } catch (e, st) {
      _isConnected = false;
      _conn = null;
      try {
        await _sshTunnelHandle?.release();
      } catch (_) {}
      _sshTunnelHandle = null;
      Error.throwWithStackTrace(
        PostgresConnectionException(
          'Failed to connect to PostgreSQL${name.isNotEmpty ? ' ($name)' : ''}: '
          '${describeDatabaseError(e, driver: DatabaseDriver.postgres)}',
          cause: e,
          stackTrace: st,
        ),
        st,
      );
    }
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _inTransaction = false;
    final c = _conn;
    _conn = null;
    try {
      await c?.close();
    } catch (e) {
      debugPrint('PostgresConnection.disconnect: $e');
    }
    try {
      await _sshTunnelHandle?.release();
    } catch (e) {
      debugPrint('PostgresConnection.sshRelease: $e');
    }
    _sshTunnelHandle = null;
  }

  /// Drops the TCP session immediately (kills pending client I/O). Used when
  /// cancelling a long query or [PostgresService.interrupt].
  Future<void> forceClose() async {
    _isConnected = false;
    _inTransaction = false;
    final c = _conn;
    _conn = null;
    try {
      await c?.close(force: true);
    } catch (e) {
      debugPrint('PostgresConnection.forceClose: $e');
    }
    try {
      await _sshTunnelHandle?.release();
    } catch (e) {
      debugPrint('PostgresConnection.forceClose ssh: $e');
    }
    _sshTunnelHandle = null;
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

  /// Session settings of a pool slot: the read-only default and, when the slot
  /// has one, a server-side statement timeout.
  Future<void> configureSession({
    required bool readOnly,
    Duration? statementTimeout,
  }) async {
    await setSessionReadOnly(readOnly);
    if (statementTimeout != null) {
      await execute(
        'SET statement_timeout = ${statementTimeout.inMilliseconds}',
      );
    }
  }

  /// Tests connectivity and returns a result with an optional error message.
  Future<({bool ok, String? error})> testConnection() async {
    try {
      await connect();
      if (_conn != null) {
        await _queued((c) => c.execute('SELECT 1'));
        return (ok: true, error: null);
      }
      return (ok: false, error: 'Connection could not be established.');
    } on PostgresConnectionException catch (e) {
      return (ok: false, error: e.message);
    } catch (e) {
      return (ok: false, error: e.toString());
    } finally {
      await disconnect();
    }
  }

  /// Runs SQL on the underlying session, one statement at a time. [timeout]
  /// overrides [ConnectionSettings.queryTimeout] for this statement and starts
  /// when the statement does.
  ///
  /// A server-side cancel (SQLSTATE 57014) arrives as a [PgException], and the
  /// session stays usable. Only a bare [TimeoutException] closes it: then the
  /// protocol may be out of step.
  Future<Result> execute(String sql, {Duration? timeout}) {
    return statementQueue.run(() async {
      final seam = runStatementForTest;
      final c = _conn;
      if (seam == null && (!isConnected || c == null)) {
        throw StateError('Not connected to PostgreSQL');
      }
      try {
        final result = seam != null
            ? await seam(sql, timeout)
            : await c!.execute(sql, timeout: timeout);
        _inTransaction = applyPostgresTransactionSql(_inTransaction, sql);
        return result;
      } on TimeoutException catch (e) {
        if (e is! PgException) unawaited(forceClose());
        rethrow;
      }
    });
  }

  /// A driver call on this session in its turn of [statementQueue], for the
  /// metadata and stats queries. Without the queue the driver would start the
  /// call's default timeout while it waits, and could cancel the statement
  /// that is running (#1216).
  Future<Result> _queued(Future<Result> Function(Connection c) call) =>
      statementQueue.run(() {
        final c = _conn;
        if (!isConnected || c == null) {
          throw StateError('Not connected to PostgreSQL');
        }
        return call(c);
      });

  /// [execute] with [timeout] as the statement's own limit. The limit starts
  /// when the statement starts: time spent waiting behind another statement on
  /// this session does not count against it.
  Future<Result> executeWithTimeout(
    String sql, {
    Duration? timeout,
  }) =>
      execute(sql, timeout: timeout);

  /// Whether the session has an open transaction.
  ///
  /// `BEGIN` + `SELECT` does not assign an XID, so `pg_current_xact_id_if_assigned`
  /// stays NULL. We track BEGIN/COMMIT/ROLLBACK on [execute], and otherwise
  /// probe `pg_stat_activity.xact_start` for this backend (PG 9+; no PG 13
  /// requirement). Returns `null` only when disconnected.
  Future<bool?> inOpenTransaction() async {
    if (!isConnected || _conn == null) return null;
    if (_inTransaction) return true;
    try {
      final r = await _queued((c) => c.execute(kPostgresOpenTransactionProbeSql));
      if (r.isEmpty) return false;
      final open = r.first[0] == true;
      _inTransaction = open;
      return open;
    } catch (e) {
      debugPrint('PostgresConnection.inOpenTransaction: $e');
      return _inTransaction;
    }
  }

  Future<List<String>> listDatabases() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      "SELECT datname FROM pg_database WHERE datistemplate = false ORDER BY datname",
    ));
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listSchemas() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      "SELECT schema_name FROM information_schema.schemata "
      "WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') "
      "ORDER BY schema_name",
    ));
    return result.map((row) => row[0] as String).toList();
  }

  /// Tables, views, and materialized views across user schemas (Quick Switcher).
  Future<List<({String schema, String name, String kind})>>
      listBrowsableRelations() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      "SELECT n.nspname::text, c.relname::text, "
      "CASE c.relkind "
      "WHEN 'r' THEN 'table' "
      "WHEN 'p' THEN 'table' "
      "WHEN 'v' THEN 'view' "
      "WHEN 'm' THEN 'matview' "
      "END "
      "FROM pg_class c "
      "JOIN pg_namespace n ON n.oid = c.relnamespace "
      "WHERE c.relkind IN ('r', 'p', 'v', 'm') "
      "AND n.nspname NOT IN ('pg_catalog', 'information_schema', 'pg_toast') "
      "AND n.nspname NOT LIKE 'pg_temp%' "
      "AND n.nspname NOT LIKE 'pg_toast_temp%' "
      "ORDER BY 1, 2",
    ));
    return [
      for (final row in result)
        (
          schema: row[0] as String,
          name: row[1] as String,
          kind: row[2] as String? ?? 'table',
        ),
    ];
  }

  Future<List<String>> listTables({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      Sql.named(
        "SELECT table_name FROM information_schema.tables "
        "WHERE table_schema = @schema AND table_type = 'BASE TABLE' "
        "ORDER BY table_name",
      ),
      parameters: {'schema': schema},
    ));
    return result.map((row) => row[0] as String).toList();
  }

  /// Retrieves schema metadata and primary keys for [table] in [schema].
  Future<TableSchemaMeta> getTableSchema({
    String schema = 'public',
    required String table,
  }) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final colsRs = await _queued((c) => c.execute(
      Sql.named(
        'SELECT column_name, data_type, udt_name, is_nullable, column_default, '
        'is_generated, is_identity, identity_generation '
        'FROM information_schema.columns '
        'WHERE table_schema = @schema AND table_name = @table '
        'ORDER BY ordinal_position',
      ),
      parameters: {'schema': schema, 'table': table},
    ));

    final pkRs = await _queued((c) => c.execute(
      Sql.named(
        'SELECT kcu.column_name '
        'FROM information_schema.table_constraints tc '
        'JOIN information_schema.key_column_usage kcu '
        '  ON tc.constraint_name = kcu.constraint_name '
        ' AND tc.table_schema = kcu.table_schema '
        "WHERE tc.constraint_type = 'PRIMARY KEY' "
        '  AND tc.table_schema = @schema '
        '  AND tc.table_name = @table '
        'ORDER BY kcu.ordinal_position',
      ),
      parameters: {'schema': schema, 'table': table},
    ));

    final primaryKeys = pkRs.map((r) => r[0] as String).toList();
    final columns = <TableColumnMeta>[];

    for (final r in colsRs) {
      final name = r[0] as String? ?? '';
      final dataType = postgresColumnSchemaType(
        dataType: r[1] as String? ?? '',
        udtName: r[2] as String? ?? '',
      );
      final isNullable = (r[3] as String? ?? 'YES').toUpperCase() == 'YES';
      final isPk = primaryKeys.contains(name);
      final pkPos = isPk ? primaryKeys.indexOf(name) + 1 : null;
      final dflt = r[4]?.toString();
      final isGenerated =
          (r[5] as String? ?? 'NEVER').toUpperCase() == 'ALWAYS';
      final isIdentity = (r[6] as String? ?? 'NO').toUpperCase() == 'YES';
      final identityGeneration = (r[7] as String? ?? '').toUpperCase();
      final omitOnInsert =
          isGenerated || (isIdentity && identityGeneration == 'ALWAYS');
      final hasServerDefault = (dflt != null && dflt.isNotEmpty) ||
          (isIdentity && identityGeneration == 'BY DEFAULT');

      columns.add(
        TableColumnMeta(
          name: name,
          dataType: dataType,
          isNullable: isNullable,
          isPrimaryKey: isPk,
          primaryKeyPosition: pkPos,
          defaultValue: dflt,
          omitOnInsert: omitOnInsert,
          hasServerDefault: hasServerDefault,
        ),
      );
    }

    return TableSchemaMeta(
      tableName: table,
      schema: schema,
      columns: columns,
      primaryKeys: primaryKeys,
    );
  }

  /// Planner row estimate (`pg_class.reltuples`), not a blocking `COUNT(*)`.
  /// Unanalyzed relations (`-1`) and missing catalog rows return `null`.
  Future<int?> estimateTableRows({
    String schema = 'public',
    required String table,
  }) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      Sql.named(
        'SELECT c.reltuples FROM pg_catalog.pg_class c '
        'JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace '
        'WHERE n.nspname = @schema AND c.relname = @table '
        "AND c.relkind IN ('r', 'p', 'm', 'f') "
        'LIMIT 1',
      ),
      parameters: {'schema': schema, 'table': table},
    ));
    if (result.isEmpty) return null;
    return postgresReltuplesEstimate(result.first[0]);
  }

  /// Returns primary key column names for [table] in [schema].
  Future<List<String>> getPrimaryKeys({
    String schema = 'public',
    required String table,
  }) async {
    final s = await getTableSchema(schema: schema, table: table);
    return s.primaryKeys;
  }

  Future<List<String>> listViews({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      Sql.named(
        "SELECT table_name FROM information_schema.views "
        "WHERE table_schema = @schema "
        "ORDER BY table_name",
      ),
      parameters: {'schema': schema},
    ));
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listFunctions({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      Sql.named(
        "SELECT routine_name FROM information_schema.routines "
        "WHERE routine_schema = @schema AND routine_type = 'FUNCTION' "
        "ORDER BY routine_name",
      ),
      parameters: {'schema': schema},
    ));
    return result.map((row) => row[0] as String).toList();
  }

  Future<List<String>> listSequences({String schema = 'public'}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
      Sql.named(
        "SELECT sequence_name FROM information_schema.sequences "
        "WHERE sequence_schema = @schema "
        "ORDER BY sequence_name",
      ),
      parameters: {'schema': schema},
    ));
    return result.map((row) => row[0] as String).toList();
  }

  Future<String> serverVersion() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute('SELECT version()'));
    return result.first[0] as String;
  }

  /// Fetches key server statistics for the stats dashboard.
  Future<Map<String, dynamic>> serverStats() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final stats = <String, dynamic>{};

    final ver = await _queued((c) => c.execute('SELECT version()'));
    stats['version'] = ver.first[0] as String;

    final settings = await _queued((c) => c.execute(
      "SELECT name, setting FROM pg_settings "
      "WHERE name IN ('max_connections','shared_buffers','work_mem',"
      "'effective_cache_size','server_version','data_directory',"
      "'listen_addresses','port','server_encoding','timezone')",
    ));
    final settingsMap = <String, String>{};
    for (final row in settings) {
      settingsMap[row[0] as String] = row[1] as String;
    }
    stats['settings'] = settingsMap;

    final activity = await _queued((c) => c.execute(
      "SELECT count(*) AS total, "
      "count(*) FILTER (WHERE state = 'active') AS active, "
      "count(*) FILTER (WHERE state = 'idle') AS idle "
      "FROM pg_stat_activity",
    ));
    if (activity.isNotEmpty) {
      stats['connections_total'] = activity.first[0];
      stats['connections_active'] = activity.first[1];
      stats['connections_idle'] = activity.first[2];
    }

    final dbStats = await _queued((c) => c.execute(
      "SELECT datname, pg_database_size(datname) AS size, "
      "numbackends, xact_commit, xact_rollback, blks_read, blks_hit, "
      "tup_returned, tup_fetched, tup_inserted, tup_updated, tup_deleted "
      "FROM pg_stat_database WHERE datname NOT LIKE 'template%' "
      "ORDER BY datname",
    ));
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
      final uptime = await _queued((c) => c.execute(
        "SELECT extract(epoch from (now() - pg_postmaster_start_time()))::bigint",
      ));
      stats['uptime_seconds'] = uptime.first[0];
    } catch (e) {
      debugPrint('PostgresConnection.getServerStats uptime: $e');
    }

    try {
      final dbSize = await _queued((c) => c.execute(
        "SELECT pg_database_size(current_database())",
      ));
      stats['current_db_size'] = dbSize.first[0];
    } catch (e) {
      debugPrint('PostgresConnection.getServerStats database size: $e');
    }

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
      sslRootCert: sslRootCert,
      sslCert: sslCert,
      sslKey: sslKey,
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
    final result = await _queued((c) => c.execute(
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
    ));
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
    final result = await _queued((c) => c.execute(
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
    ));
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
    final result = await _queued((c) => c.execute(
      Sql.named(
        'SELECT matviewname FROM pg_matviews WHERE schemaname = @schema '
        'ORDER BY matviewname',
      ),
      parameters: {'schema': schema},
    ));
    return result.map((row) => row[0] as String).toList();
  }

  Future<void> refreshMaterializedView(String schema, String name) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final q = '${_quoteIdent(schema)}.${_quoteIdent(name)}';
    await _queued((c) => c.execute('REFRESH MATERIALIZED VIEW $q'));
  }

  Future<List<PgIndexRow>> listIndexesInSchema(String schema) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to PostgreSQL');
    }
    final result = await _queued((c) => c.execute(
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
    ));
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
    final result = await _queued((c) => c.execute(
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
    ));
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
    final result = await _queued((c) => c.execute(
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
    ));
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
    final result = await _queued((c) => c.execute(
      'SELECT extname::text, extversion::text FROM pg_extension ORDER BY extname',
    ));
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
    final result = await _queued((c) => c.execute(
      r'''
SELECT fdwname::text, fdwhandler::regproc::text
FROM pg_foreign_data_wrapper
ORDER BY fdwname
''',
    ));
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
    final result = await _queued((c) => c.execute(
      r'''
SELECT s.srvname::text, w.fdwname::text
FROM pg_foreign_server s
JOIN pg_foreign_data_wrapper w ON w.oid = s.srvfdw
ORDER BY s.srvname
''',
    ));
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
    final result = await _queued((c) => c.execute(
      Sql.named(
        r'''
SELECT grantee::text, privilege_type::text, is_grantable::text
FROM information_schema.role_table_grants
WHERE table_schema = @schema AND table_name = @table
ORDER BY grantee, privilege_type
''',
      ),
      parameters: {'schema': schema, 'table': table},
    ));
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

  static String _quoteIdent(String id) => '"${id.replaceAll('"', '""')}"';

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
  PostgresConnectionException(
    this.message, {
    this.cause,
    this.stackTrace,
  });

  final String message;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => message;
}
