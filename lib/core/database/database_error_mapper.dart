import 'dart:async';
import 'dart:io';

import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/querya_database_exception.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/statement_queue.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// Which engine produced an error; only used to tailor the wording.
enum DatabaseDriver { postgres, mysql, sqlite, mongodb, redis, extension }

/// Maps a driver / OS error to a [QueryaDatabaseException].
///
/// Already-mapped exceptions are returned as is. Unrecognized errors become an
/// [UnknownDatabaseException] that keeps the original text.
QueryaDatabaseException mapDatabaseError(
  Object error, {
  StackTrace? stackTrace,
  DatabaseDriver? driver,
}) {
  if (error is QueryaDatabaseException) return error;
  if (error is SecretsStoreUnavailableException) {
    // Not a wrong password: the saved one could not be read at all (#1303).
    return UnknownDatabaseException(
      SecretsStoreUnavailableException.message,
      detailedExplanation: error.cause.toString(),
      remediationHint: SecretsStoreUnavailableException.hint,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  final raw = _fullText(error);
  final lower = raw.toLowerCase();
  final engine = _engineName(driver);

  QueryaDatabaseException? mapped;

  if (error is StatementWaitTimeoutException) {
    mapped = ConnectionTimeoutException(
      error.message,
      remediationHint: 'Wait for the running statement to finish, or cancel '
          'it, then try again',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_hasAny(lower, const [
    'lock wait timeout',
    'lock timeout',
    'database is locked',
    'sqlite_busy',
    'sqlite is busy',
    'deadlock detected',
    'deadlock found',
  ])) {
    mapped = LockTimeoutException(
      'The database is locked by another operation',
      remediationHint:
          'Commit or roll back any open transaction and try again in a moment',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_hasAny(lower, const [
    'password authentication failed',
    'access denied for user',
    'authentication failed',
    'auth failed',
    'wrongpass',
    'noauth',
    'invalid password',
    'invalid username-password',
    'sqlstate 28p01',
    'sqlstate 28000',
  ])) {
    mapped = AuthFailedException(
      'Authentication failed',
      detailedExplanation: '$engine rejected the supplied credentials.',
      remediationHint: driver == DatabaseDriver.redis
          ? 'Check the username and password (the server may require '
              '"requirepass" or an ACL user)'
          : 'Check the username and password in the connection settings',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_firstMatch(raw, [
        RegExp(r'database "([^"]+)" does not exist', caseSensitive: false),
        RegExp(r"unknown database '([^']+)'", caseSensitive: false),
      ])
      case final db?) {
    mapped = DatabaseNotFoundException(
      'Database "$db" does not exist',
      databaseName: db,
      remediationHint:
          'Check the database name in the connection settings or create it first',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_columnMatch(raw) case final column?) {
    // Before the table patterns: `column "x" of relation "t" does not exist`
    // contains `relation "t" does not exist` and is not a missing table.
    mapped = ColumnNotFoundException(
      column.table == null
          ? 'Column "${column.name}" does not exist'
          : 'Column "${column.name}" does not exist in "${column.table}"',
      columnName: column.name,
      tableName: column.table,
      remediationHint:
          'Check the column name, or refresh the object tree if it was added '
          'or renamed',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_firstMatch(raw, [
        RegExp(r'relation "([^"]+)" does not exist', caseSensitive: false),
        RegExp(r"table '([^']+)' doesn't exist", caseSensitive: false),
        RegExp(r'no such table: ([\w."]+)', caseSensitive: false),
      ])
      case final table?) {
    mapped = TableNotFoundException(
      'Table "$table" does not exist',
      tableName: table,
      remediationHint:
          'Check the table name and schema, or refresh the object tree',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_hasAny(lower, const [
    'syntax error',
    'error in your sql syntax',
    'err syntax',
  ])) {
    mapped = QuerySyntaxException(
      'Syntax error in the query',
      detailedExplanation: _innermost(raw),
      remediationHint: 'Fix the statement near the position reported by the '
          'server and run it again',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (error is TlsException ||
      _hasAny(lower, const [
        'certificate_verify_failed',
        'certificate verify failed',
        'handshakeexception',
        'handshake error',
        'unknown ca',
        'self signed certificate',
        'self-signed certificate',
        'unable to get local issuer',
        'certificate has expired',
        'hostname mismatch',
        'wrong version number',
        'tlsv1 alert',
        'ssl routines',
        'server does not support ssl',
      ])) {
    mapped = TlsFailureException(
      'The secure (TLS) connection to the server could not be established',
      detailedExplanation: _innermost(raw),
      remediationHint: 'Check the SSL mode and the root certificate in the '
          'connection settings; a server without TLS needs SSL turned off',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (_hasAny(lower, const [
    'connection reset by peer',
    'broken pipe',
    'connection closed',
    'connection is closed',
    'connection was closed',
    'connection terminated',
    'terminating connection',
    'server closed the connection',
    'unexpected eof',
    'the database system is shutting down',
    'the database system is restarting',
    'lost connection to mysql server',
    'mysql server has gone away',
    'connection lost',
  ])) {
    mapped = ConnectionLostException(
      'The connection to the database was lost',
      detailedExplanation: _innermost(raw),
      remediationHint: 'The server closed the session (a restart, an idle '
          'timeout or a network drop). Reconnect and try again',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (error is TimeoutException ||
      _hasAny(lower, const ['timed out', 'timeout expired', 'etimedout'])) {
    mapped = ConnectionTimeoutException(
      'The operation timed out',
      remediationHint: 'Check the network and firewall, or that the server '
          'is not overloaded, then try again',
      originalError: error,
      stackTrace: stackTrace,
    );
  } else if (error is SocketException ||
      _hasAny(lower, const [
        'connection refused',
        'failed host lookup',
        'no route to host',
        'network is unreachable',
        'name or service not known',
        'econnrefused',
        'socketexception',
      ])) {
    mapped = HostUnreachableException(
      'Cannot reach the database server',
      detailedExplanation: '$engine did not accept the connection.',
      remediationHint: 'Check the host and port, that the server is running, '
          'and any firewall or SSH tunnel settings',
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  return mapped ??
      UnknownDatabaseException(
        _innermost(raw),
        originalError: error,
        stackTrace: stackTrace,
      );
}

/// One-line, user-facing text for [error] (message plus remediation hint).
///
/// Unrecognized errors keep their original text, so callers can use this in
/// place of `error.toString()` without losing information.
String describeDatabaseError(Object error, {DatabaseDriver? driver}) {
  final mapped = mapDatabaseError(error, driver: driver);
  if (mapped is UnknownDatabaseException) return error.toString();
  return mapped.displayText;
}

String _engineName(DatabaseDriver? driver) => switch (driver) {
      DatabaseDriver.postgres => 'PostgreSQL',
      DatabaseDriver.mysql => 'MySQL',
      DatabaseDriver.sqlite => 'SQLite',
      DatabaseDriver.mongodb => 'MongoDB',
      DatabaseDriver.redis => 'Redis',
      DatabaseDriver.extension => 'The extension driver',
      null => 'The server',
    };

/// Error text including the wrapped `cause` of the connection exceptions.
String _fullText(Object error) {
  final parts = <String>[error.toString()];
  final cause = switch (error) {
    PostgresConnectionException(:final cause) => cause,
    MysqlConnectionException(:final cause) => cause,
    SqliteConnectionException(:final cause) => cause,
    _ => null,
  };
  if (cause != null) parts.add(cause.toString());
  if (error is RedisConnectionException) parts.add(error.message);
  return parts.join('\n');
}

String _innermost(String raw) {
  final line = raw.split('\n').first.trim();
  final i = line.lastIndexOf(': ');
  final tail = i >= 0 ? line.substring(i + 2).trim() : line;
  return tail.isEmpty ? line : tail;
}

bool _hasAny(String lower, List<String> needles) =>
    needles.any(lower.contains);

/// A missing column in the words of PostgreSQL, MySQL or SQLite.
({String name, String? table})? _columnMatch(String raw) {
  final pg = RegExp(
    r'column "([^"]+)" of relation "([^"]+)" does not exist',
    caseSensitive: false,
  ).firstMatch(raw);
  if (pg != null) return (name: pg.group(1)!, table: pg.group(2));
  for (final p in [
    RegExp(r'column "([^"]+)" does not exist', caseSensitive: false),
    RegExp(r"unknown column '([^']+)'", caseSensitive: false),
    RegExp(r'no such column: ([\w."]+)', caseSensitive: false),
  ]) {
    final m = p.firstMatch(raw);
    if (m != null) return (name: m.group(1)!, table: null);
  }
  return null;
}

String? _firstMatch(String text, List<RegExp> patterns) {
  for (final p in patterns) {
    final m = p.firstMatch(text);
    if (m != null) return m.group(1);
  }
  return null;
}

/// Rethrows [error] as a recognized [QueryaDatabaseException], or unchanged
/// when it is not recognized (so existing typed errors keep their type).
Never rethrowMappedDatabaseError(
  Object error,
  StackTrace stackTrace, {
  DatabaseDriver? driver,
}) {
  final mapped = mapDatabaseError(error, stackTrace: stackTrace, driver: driver);
  Error.throwWithStackTrace(
    mapped is UnknownDatabaseException ? error : mapped,
    stackTrace,
  );
}
