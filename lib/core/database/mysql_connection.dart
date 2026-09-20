import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/security/ssl_certificate_support.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// TLS policy from `ssl-mode` / `sslmode` / `ssl` on a MySQL URI.
enum MysqlSslMode {
  disable,
  encrypt,
  verifyCa,
  verifyIdentity,
}

extension MysqlSslModeX on MysqlSslMode {
  bool get secure => this != MysqlSslMode.disable;
  bool get verifyCertificates =>
      this == MysqlSslMode.verifyCa || this == MysqlSslMode.verifyIdentity;
  bool get verifyIdentity => this == MysqlSslMode.verifyIdentity;
}

/// Parses Connector/J-style `ssl-mode` (`prefer` is TLS on, not disable).
MysqlSslMode parseMysqlSslMode(String? raw, {required bool fallbackSsl}) {
  if (raw == null || raw.trim().isEmpty) {
    return fallbackSsl ? MysqlSslMode.encrypt : MysqlSslMode.disable;
  }
  switch (raw.toLowerCase().replaceAll('-', '_')) {
    case 'false':
    case '0':
    case 'disable':
    case 'disabled':
      return MysqlSslMode.disable;
    case 'prefer':
    case 'preferred':
    case 'require':
    case 'required':
    case 'true':
    case '1':
    case 'enabled':
      return MysqlSslMode.encrypt;
    case 'verify_ca':
      return MysqlSslMode.verifyCa;
    case 'verify_identity':
    case 'verify_full':
      return MysqlSslMode.verifyIdentity;
    default:
      return fallbackSsl ? MysqlSslMode.encrypt : MysqlSslMode.disable;
  }
}

/// `verify_ca` / `verify_identity` fail closed without `sslrootcert`.
void validateMysqlSslMode(MysqlSslMode mode, SslCertificatePaths paths) {
  if (!mode.verifyCertificates) return;
  final ca = paths.rootCert?.trim() ?? '';
  if (ca.isEmpty) {
    final label =
        mode == MysqlSslMode.verifyIdentity ? 'verify_identity' : 'verify_ca';
    throw ArgumentError('ssl-mode=$label requires sslrootcert');
  }
}

/// Replaces the database in a `mysql://` / `mariadb://` URI (path or `database=`).
String replaceDatabaseInMysqlConnectionString(
  String connectionString,
  String newDatabase,
) {
  final uri = Uri.parse(connectionString.trim());
  if (uri.scheme != 'mysql' && uri.scheme != 'mariadb') {
    throw ArgumentError(
      'Invalid connection string scheme: ${uri.scheme}. '
      'Expected "mysql" or "mariadb".',
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

/// Pure-Dart MySQL client wrapper around [MySQLConnection] (`mysql_client`).
class MysqlConnection {
  MysqlConnection({
    required this.id,
    required this.name,
    required this.host,
    this.port = 3306,
    this.username,
    String? password,
    this.database,
    this.useSSL = true,
    String? connectionString,
  })  : _password = password,
        _connectionString = connectionString;

  factory MysqlConnection.fromConnectionRow(
    ConnectionRow row, {
    String? database,
  }) {
    return MysqlConnection(
      id: row.id ?? 0,
      name: row.name,
      host: row.host ?? 'localhost',
      port: row.port ?? 3306,
      username: row.username,
      password: row.password,
      database: database ?? row.databaseName,
      useSSL: row.useSSL,
      connectionString: row.connectionString,
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

  String? get password => _password;
  String? get connectionString => _connectionString;

  MySQLConnection? _conn;
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

  /// MySQL identifier quoting (backticks).
  static String quoteIdentifier(String id) {
    return '`${id.replaceAll('`', '``')}`';
  }

  Future<void> connect({int connectTimeoutMs = 10000}) async {
    if (_isConnected && _conn != null) return;

    var effectivePassword = _password;
    var effectiveConnectionString = _connectionString;

    if ((effectivePassword == null || effectivePassword.isEmpty) &&
        (effectiveConnectionString == null ||
            effectiveConnectionString.isEmpty) &&
        id > 0) {
      try {
        final secrets = await ConnectionSecretsStore.readForConnection(id);
        effectivePassword = secrets.password;
        effectiveConnectionString = secrets.connectionString;
      } catch (_) {}
    }

    try {
      final user = username ?? '';
      final pass = effectivePassword ?? '';
      if (_usesConnectionString(effectiveConnectionString)) {
        final dbName = database;
        final uriStr = dbName != null && dbName.isNotEmpty
            ? replaceDatabaseInMysqlConnectionString(
                effectiveConnectionString!.trim(),
                dbName,
              )
            : effectiveConnectionString!.trim();
        final parsed = _parseMysqlUri(uriStr, fallbackSsl: useSSL);
        final sslPaths = extractSslCertificatePathsFromString(uriStr);
        var sslMode = parsed.sslMode;
        if (sslPaths.hasAny && sslMode == MysqlSslMode.disable) {
          sslMode = MysqlSslMode.encrypt;
        }
        validateMysqlSslMode(sslMode, sslPaths);
        final securityContext = buildSecurityContext(sslPaths);
        final host = parsed.host;
        _conn = await MySQLConnection.createConnection(
          host: host,
          port: parsed.port,
          userName: parsed.userName,
          password: parsed.password,
          secure: sslMode.secure,
          databaseName: parsed.databaseName,
          securityContext: securityContext,
          sslVerifyCertificates: sslMode.verifyCertificates,
          sslServerName: sslMode.verifyIdentity && host is String ? host : null,
        );
        await _conn!.connect(timeoutMs: connectTimeoutMs);
      } else {
        final sslPaths =
            extractSslCertificatePathsFromString(effectiveConnectionString);
        final securityContext = buildSecurityContext(sslPaths);
        _conn = await MySQLConnection.createConnection(
          host: host,
          port: port,
          userName: user,
          password: pass,
          secure: useSSL || sslPaths.hasAny,
          databaseName: database,
          securityContext: securityContext,
        );
        await _conn!.connect(timeoutMs: connectTimeoutMs);
      }
      _isConnected = true;
      scrubCredentials();
    } catch (e) {
      _isConnected = false;
      _conn = null;
      rethrow;
    }
  }

  /// Parsed URI fields for `mysql://` / `mariadb://`.
  static ({
    dynamic host,
    int port,
    String userName,
    String password,
    String? databaseName,
    MysqlSslMode sslMode,
  }) _parseMysqlUri(String raw, {required bool fallbackSsl}) {
    final uri = Uri.parse(raw);
    if (uri.scheme != 'mysql' && uri.scheme != 'mariadb') {
      throw ArgumentError('Expected mysql or mariadb scheme');
    }
    final hostStr = uri.host.isEmpty ? 'localhost' : uri.host;
    final port = uri.hasPort ? uri.port : 3306;

    String userName = '';
    String password = '';
    final info = uri.userInfo;
    if (info.isNotEmpty) {
      final colon = info.indexOf(':');
      if (colon >= 0) {
        userName = Uri.decodeComponent(info.substring(0, colon));
        password = Uri.decodeComponent(info.substring(colon + 1));
      } else {
        userName = Uri.decodeComponent(info);
      }
    }

    String? db;
    if (uri.pathSegments.isNotEmpty && uri.pathSegments.first.isNotEmpty) {
      db = Uri.decodeComponent(uri.pathSegments.first);
    }
    db ??= uri.queryParameters['database'];

    final q = uri.queryParameters;
    var sslMode = parseMysqlSslMode(
      q['ssl-mode'] ?? q['sslmode'] ?? q['ssl'],
      fallbackSsl: fallbackSsl,
    );
    if (q.containsKey(kSslRootCertParam) ||
        q.containsKey(kSslCertParam) ||
        q.containsKey(kSslKeyParam)) {
      if (sslMode == MysqlSslMode.disable) {
        sslMode = MysqlSslMode.encrypt;
      }
    }

    return (
      host: hostStr,
      port: port,
      userName: userName,
      password: password,
      databaseName: db,
      sslMode: sslMode,
    );
  }

  /// Parsed `ssl-mode` for [connectionString] (tests).
  @visibleForTesting
  static MysqlSslMode sslModeFromConnectionString(
    String connectionString, {
    bool fallbackSsl = true,
  }) {
    return _parseMysqlUri(connectionString, fallbackSsl: fallbackSsl).sslMode;
  }

  /// Whether [connectionString] implies a TLS session (including cert query params).
  @visibleForTesting
  static bool connectionStringRequiresSsl(
    String connectionString, {
    bool fallbackSsl = true,
  }) {
    return _parseMysqlUri(connectionString, fallbackSsl: fallbackSsl)
        .sslMode
        .secure;
  }

  Future<void> disconnect() async {
    _isConnected = false;
    _inTransaction = false;
    final c = _conn;
    _conn = null;
    try {
      if (c != null && c.connected) {
        await c.close();
      }
    } catch (e) {
      debugPrint('MysqlConnection.disconnect: $e');
    }
  }

  /// Best-effort close. The `mysql_client` driver may not allow graceful [close]
  /// while a query is in progress.
  Future<void> forceClose() async {
    _isConnected = false;
    _inTransaction = false;
    final c = _conn;
    _conn = null;
    if (c == null) return;
    try {
      if (c.connected) {
        await c.close();
      }
    } catch (e) {
      debugPrint('MysqlConnection.forceClose: $e');
    }
  }

  /// Session hint for read-only browsing (MySQL 8+ / MariaDB — semantics differ from PostgreSQL).
  Future<void> setSessionReadOnly(bool readOnly) async {
    if (!isConnected || _conn == null) return;
    if (readOnly) {
      await execute('SET SESSION TRANSACTION READ ONLY');
    } else {
      await execute('SET SESSION TRANSACTION READ WRITE');
    }
  }

  Future<bool> testConnection() async {
    try {
      await connect();
      if (_conn != null) {
        await execute('SELECT 1');
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('MysqlConnection.testConnection: $e');
      return false;
    } finally {
      await disconnect();
    }
  }

  Future<IResultSet> execute(
    String sql, [
    Map<String, dynamic>? params,
    bool iterable = false,
  ]) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    try {
      final rs = await _conn!.execute(sql, params, iterable);
      _noteTransactionSql(sql);
      return rs;
    } on TimeoutException {
      unawaited(forceClose());
      rethrow;
    }
  }

  /// Whether this session has an open `START TRANSACTION` / `BEGIN`.
  Future<bool?> inOpenTransaction() async {
    if (!isConnected) return null;
    return _inTransaction;
  }

  /// Runs [body] inside a transaction. If the session already has one, DML
  /// joins it instead of nesting `START TRANSACTION`.
  Future<void> runInTransaction(Future<void> Function() body) async {
    final join = _inTransaction;
    if (!join) {
      await execute('START TRANSACTION');
    }
    try {
      await body();
      if (!join) await execute('COMMIT');
    } catch (e) {
      if (!join) {
        try {
          await execute('ROLLBACK');
        } catch (_) {}
      }
      rethrow;
    }
  }

  void _noteTransactionSql(String sql) {
    final sqlLower = sql.trim().toLowerCase();
    if (sqlLower.startsWith('start transaction') ||
        sqlLower.startsWith('begin')) {
      _inTransaction = true;
      return;
    }
    if (sqlLower.startsWith('commit')) {
      _inTransaction = false;
      return;
    }
    if (sqlLower.startsWith('rollback') &&
        !RegExp(r'^rollback\s+to\b').hasMatch(sqlLower)) {
      _inTransaction = false;
    }
  }

  /// Runs [execute] with an application-level [timeout] (driver limits still apply).
  Future<IResultSet> executeWithTimeout(
    String sql, {
    Duration? timeout,
    Map<String, dynamic>? params,
    bool iterable = false,
  }) async {
    final f = execute(sql, params, iterable);
    if (timeout == null) return f;
    try {
      return await f.timeout(timeout);
    } on TimeoutException {
      unawaited(forceClose());
      rethrow;
    }
  }

  /// Lists user-visible databases (excludes typical system schemas).
  Future<List<String>> listDatabases() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    const system = {'information_schema', 'mysql', 'performance_schema', 'sys'};
    final rs = await execute('SHOW DATABASES');
    final out = <String>[];
    for (final row in rs.rows) {
      final name = row.colAt(0);
      if (name != null &&
          name.isNotEmpty &&
          !system.contains(name.toLowerCase())) {
        out.add(name);
      }
    }
    out.sort();
    return out;
  }

  /// Lists views in [schema] (database name).
  Future<List<String>> listViews({required String schema}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT TABLE_NAME FROM information_schema.TABLES '
      "WHERE TABLE_SCHEMA = :schema AND TABLE_TYPE = 'VIEW' "
      'ORDER BY TABLE_NAME',
      {'schema': schema},
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  /// Column names for [table] in [database] (database = schema in MySQL).
  Future<List<String>> listColumnNames({
    required String database,
    required String table,
  }) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT COLUMN_NAME FROM information_schema.COLUMNS '
      "WHERE TABLE_SCHEMA = :database AND TABLE_NAME = :table "
      'ORDER BY ORDINAL_POSITION',
      {
        'database': database,
        'table': table,
      },
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  /// Retrieves schema metadata and primary keys for [table] in [database].
  Future<TableSchemaMeta> getTableSchema({
    required String database,
    required String table,
  }) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final colsRs = await execute(
      'SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT, EXTRA '
      'FROM information_schema.COLUMNS '
      'WHERE TABLE_SCHEMA = :database AND TABLE_NAME = :table '
      'ORDER BY ORDINAL_POSITION',
      {
        'database': database,
        'table': table,
      },
    );

    final pkRs = await execute(
      'SELECT COLUMN_NAME '
      'FROM information_schema.KEY_COLUMN_USAGE '
      "WHERE CONSTRAINT_NAME = 'PRIMARY' AND TABLE_SCHEMA = :database AND TABLE_NAME = :table "
      'ORDER BY ORDINAL_POSITION',
      {
        'database': database,
        'table': table,
      },
    );

    final primaryKeys = pkRs.rows.map((r) => r.colAt(0)!).toList();
    final columns = <TableColumnMeta>[];

    for (final r in colsRs.rows) {
      final name = r.colByName('COLUMN_NAME') ?? '';
      final dataType = mysqlColumnSchemaType(
        dataType: r.colByName('DATA_TYPE') ?? '',
        columnType: r.colByName('COLUMN_TYPE') ?? '',
      );
      final isNullable =
          (r.colByName('IS_NULLABLE') ?? 'YES').toUpperCase() == 'YES';
      final isPk = primaryKeys.contains(name);
      final pkPos = isPk ? primaryKeys.indexOf(name) + 1 : null;
      final dflt = r.colByName('COLUMN_DEFAULT');
      final extra = (r.colByName('EXTRA') ?? '').toLowerCase();
      final omitOnInsert = extra.contains('auto_increment') ||
          extra.contains('virtual generated') ||
          extra.contains('stored generated');
      final hasServerDefault =
          (dflt != null && dflt.isNotEmpty) || extra.contains('auto_increment');

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
      schema: database,
      columns: columns,
      primaryKeys: primaryKeys,
    );
  }

  /// InnoDB `TABLE_ROWS` estimate (not a blocking `COUNT(*)`).
  Future<int?> estimateTableRows({
    required String database,
    required String table,
  }) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT TABLE_ROWS FROM information_schema.TABLES '
      'WHERE TABLE_SCHEMA = :database AND TABLE_NAME = :table',
      {
        'database': database,
        'table': table,
      },
    );
    if (rs.rows.isEmpty) return null;
    final v = rs.rows.first.colAt(0);
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v);
  }

  /// Returns primary key column names for [table] in [database].
  Future<List<String>> getPrimaryKeys({
    required String database,
    required String table,
  }) async {
    final schema = await getTableSchema(database: database, table: table);
    return schema.primaryKeys;
  }

  /// Lists base tables in [schema] (MySQL: database name).
  Future<List<String>> listTables({required String schema}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT TABLE_NAME FROM information_schema.TABLES '
      "WHERE TABLE_SCHEMA = :schema AND TABLE_TYPE = 'BASE TABLE' "
      'ORDER BY TABLE_NAME',
      {'schema': schema},
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  /// Lists stored procedures in [schema] (database name).
  Future<List<String>> listProcedures({required String schema}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT ROUTINE_NAME FROM information_schema.ROUTINES '
      "WHERE ROUTINE_SCHEMA = :schema AND ROUTINE_TYPE = 'PROCEDURE' "
      'ORDER BY ROUTINE_NAME',
      {'schema': schema},
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  /// Lists stored functions in [schema] (database name).
  Future<List<String>> listFunctions({required String schema}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute(
      'SELECT ROUTINE_NAME FROM information_schema.ROUTINES '
      "WHERE ROUTINE_SCHEMA = :schema AND ROUTINE_TYPE = 'FUNCTION' "
      'ORDER BY ROUTINE_NAME',
      {'schema': schema},
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  Future<String> serverVersion() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final rs = await execute('SELECT VERSION()');
    return rs.rows.first.colAt(0) ?? '';
  }

  /// Key metrics for the MySQL stats dashboard (`SHOW GLOBAL STATUS` / `VARIABLES`).
  Future<Map<String, dynamic>> serverStats() async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final stats = <String, dynamic>{};

    stats['version'] = await serverVersion();

    final status = await _showKeyValueRows(
      "SHOW GLOBAL STATUS WHERE Variable_name IN ("
      "'Uptime','Threads_connected','Threads_running','Max_used_connections',"
      "'Questions','Slow_queries','Bytes_received','Bytes_sent','Connections',"
      "'Open_tables','Opened_tables','Aborted_connects'"
      ')',
    );
    stats['status'] = status;
    stats['uptime_seconds'] = int.tryParse(status['Uptime'] ?? '') ?? 0;

    stats['variables'] = await _showKeyValueRows(
      "SHOW GLOBAL VARIABLES WHERE Variable_name IN ("
      "'max_connections','port','datadir','character_set_server',"
      "'collation_server','innodb_buffer_pool_size','version'"
      ')',
    );

    const systemSchemas = {
      'information_schema',
      'mysql',
      'performance_schema',
      'sys',
    };
    final dbRs = await execute(
      'SELECT table_schema, '
      'COALESCE(SUM(data_length + index_length), 0) AS size_bytes, '
      'COUNT(*) AS table_count '
      'FROM information_schema.tables '
      "WHERE table_schema NOT IN ('information_schema','mysql',"
      "'performance_schema','sys') "
      'GROUP BY table_schema '
      'ORDER BY table_schema',
    );
    final databases = <Map<String, dynamic>>[];
    for (final row in dbRs.rows) {
      final name = row.colAt(0);
      if (name == null || systemSchemas.contains(name.toLowerCase())) {
        continue;
      }
      databases.add({
        'name': name,
        'size': int.tryParse(row.colAt(1) ?? '') ?? 0,
        'tables': int.tryParse(row.colAt(2) ?? '') ?? 0,
      });
    }
    stats['databases'] = databases;

    return stats;
  }

  Future<Map<String, String>> _showKeyValueRows(String sql) async {
    final rs = await execute(sql);
    final out = <String, String>{};
    for (final row in rs.rows) {
      final key = row.colAt(0);
      final value = row.colAt(1);
      if (key != null && value != null) {
        out[key] = value;
      }
    }
    return out;
  }
}

class MysqlConnectionException implements Exception {
  MysqlConnectionException(
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
