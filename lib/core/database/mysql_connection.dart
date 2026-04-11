import 'dart:async';

import 'package:mysql_client/mysql_client.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

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
    this.password,
    this.database,
    this.useSSL = true,
    this.connectionString,
  });

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
  final String? password;
  final String? database;
  final bool useSSL;
  final String? connectionString;

  MySQLConnection? _conn;
  bool _isConnected = false;

  bool get isConnected => _isConnected && _conn != null;

  bool get _usesConnectionString =>
      connectionString != null && connectionString!.trim().isNotEmpty;

  static String _escapeSqlString(String s) {
    return s.replaceAll(r'\', r'\\').replaceAll("'", "''");
  }

  /// MySQL identifier quoting (backticks).
  static String quoteIdentifier(String id) {
    return '`${id.replaceAll('`', '``')}`';
  }

  Future<void> connect({int connectTimeoutMs = 10000}) async {
    if (_isConnected && _conn != null) return;
    try {
      final user = username ?? '';
      final pass = password ?? '';
      if (_usesConnectionString) {
        final dbName = database;
        final uriStr = dbName != null && dbName.isNotEmpty
            ? replaceDatabaseInMysqlConnectionString(
                connectionString!.trim(),
                dbName,
              )
            : connectionString!.trim();
        final parsed = _parseMysqlUri(uriStr, fallbackSsl: useSSL);
        _conn = await MySQLConnection.createConnection(
          host: parsed.host,
          port: parsed.port,
          userName: parsed.userName,
          password: parsed.password,
          secure: parsed.secure,
          databaseName: parsed.databaseName,
        );
        await _conn!.connect(timeoutMs: connectTimeoutMs);
      } else {
        _conn = await MySQLConnection.createConnection(
          host: host,
          port: port,
          userName: user,
          password: pass,
          secure: useSSL,
          databaseName: database,
        );
        await _conn!.connect(timeoutMs: connectTimeoutMs);
      }
      _isConnected = true;
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
    bool secure,
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
    bool secure = fallbackSsl;
    final ssl = (q['ssl-mode'] ?? q['sslmode'] ?? q['ssl'])?.toLowerCase();
    if (ssl == 'false' ||
        ssl == '0' ||
        ssl == 'disable' ||
        ssl == 'disabled' ||
        ssl == 'prefer') {
      secure = false;
    }
    if (ssl == 'require' || ssl == 'verify_ca' || ssl == 'verify_identity') {
      secure = true;
    }

    return (
      host: hostStr,
      port: port,
      userName: userName,
      password: password,
      databaseName: db,
      secure: secure,
    );
  }

  Future<void> disconnect() async {
    _isConnected = false;
    final c = _conn;
    _conn = null;
    try {
      if (c != null && c.connected) {
        await c.close();
      }
    } catch (_) {}
  }

  /// Best-effort close. The `mysql_client` driver may not allow graceful [close]
  /// while a query is in progress.
  Future<void> forceClose() async {
    _isConnected = false;
    final c = _conn;
    _conn = null;
    if (c == null) return;
    try {
      if (c.connected) {
        await c.close();
      }
    } catch (_) {}
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
    } catch (_) {
      return false;
    } finally {
      await disconnect();
    }
  }

  Future<IResultSet> execute(
    String sql, [
    Map<String, dynamic>? params,
  ]) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    return _conn!.execute(sql, params);
  }

  /// Runs [execute] with an application-level [timeout] (driver limits still apply).
  Future<IResultSet> executeWithTimeout(
    String sql, {
    Duration? timeout,
    Map<String, dynamic>? params,
  }) async {
    final f = execute(sql, params);
    if (timeout == null) return f;
    return f.timeout(timeout);
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
    final s = _escapeSqlString(schema);
    final rs = await execute(
      'SELECT TABLE_NAME FROM information_schema.TABLES '
      "WHERE TABLE_SCHEMA = '$s' AND TABLE_TYPE = 'VIEW' "
      'ORDER BY TABLE_NAME',
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
    final d = _escapeSqlString(database);
    final t = _escapeSqlString(table);
    final rs = await execute(
      'SELECT COLUMN_NAME FROM information_schema.COLUMNS '
      "WHERE TABLE_SCHEMA = '$d' AND TABLE_NAME = '$t' "
      'ORDER BY ORDINAL_POSITION',
    );
    return rs.rows.map((r) => r.colAt(0)!).toList();
  }

  /// Lists base tables in [schema] (MySQL: database name).
  Future<List<String>> listTables({required String schema}) async {
    if (!isConnected || _conn == null) {
      throw StateError('Not connected to MySQL');
    }
    final s = _escapeSqlString(schema);
    final rs = await execute(
      'SELECT TABLE_NAME FROM information_schema.TABLES '
      "WHERE TABLE_SCHEMA = '$s' AND TABLE_TYPE = 'BASE TABLE' "
      'ORDER BY TABLE_NAME',
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
}
