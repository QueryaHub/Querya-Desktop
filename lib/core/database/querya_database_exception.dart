/// Driver-independent database failure with a user-facing explanation.
///
/// Drivers throw their own low-level errors (`PgException`, `MySQLException`,
/// `MongoDartError`, `SocketException`, `StateError`, ...). Those are mapped
/// into this hierarchy by `mapDatabaseError` so the UI can show a plain
/// message plus a [remediationHint] instead of a raw driver string.
sealed class QueryaDatabaseException implements Exception {
  const QueryaDatabaseException(
    this.message, {
    this.detailedExplanation,
    this.remediationHint,
    this.originalError,
    this.stackTrace,
  });

  /// Short, plain-language summary (one line).
  final String message;

  /// Longer explanation of what went wrong, when it adds information.
  final String? detailedExplanation;

  /// What the user can do to fix the problem.
  final String? remediationHint;

  /// The driver error this was mapped from.
  final Object? originalError;
  final StackTrace? stackTrace;

  /// [message] followed by the remediation hint, for single-string surfaces
  /// such as tree errors, the status bar and toasts.
  String get displayText => remediationHint == null || remediationHint!.isEmpty
      ? message
      : '$message. $remediationHint';

  @override
  String toString() => displayText;
}

/// Wrong or missing credentials.
final class AuthFailedException extends QueryaDatabaseException {
  const AuthFailedException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// The server could not be reached (refused, DNS failure, no route).
final class HostUnreachableException extends QueryaDatabaseException {
  const HostUnreachableException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// Connecting or running a command took longer than the allowed time.
final class ConnectionTimeoutException extends QueryaDatabaseException {
  const ConnectionTimeoutException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// The requested database / schema does not exist on the server.
final class DatabaseNotFoundException extends QueryaDatabaseException {
  const DatabaseNotFoundException(
    super.message, {
    this.databaseName,
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });

  final String? databaseName;
}

/// The statement or command could not be parsed.
final class QuerySyntaxException extends QueryaDatabaseException {
  const QuerySyntaxException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// A table / relation referenced by a statement does not exist.
final class TableNotFoundException extends QueryaDatabaseException {
  const TableNotFoundException(
    super.message, {
    this.tableName,
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });

  final String? tableName;
}

/// A column referenced by a statement does not exist (#1310).
final class ColumnNotFoundException extends QueryaDatabaseException {
  const ColumnNotFoundException(
    super.message, {
    this.columnName,
    this.tableName,
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });

  final String? columnName;
  final String? tableName;
}

/// A lock could not be acquired in time (busy / locked / deadlock).
final class LockTimeoutException extends QueryaDatabaseException {
  const LockTimeoutException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// An established session was closed under the client: the server restarted
/// or closed an idle session, or the network dropped (#1316).
final class ConnectionLostException extends QueryaDatabaseException {
  const ConnectionLostException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// The TLS handshake or the server certificate was rejected (#1316).
final class TlsFailureException extends QueryaDatabaseException {
  const TlsFailureException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// Every slot of a connection pool is in use (#1316).
final class PoolExhaustedException extends QueryaDatabaseException {
  const PoolExhaustedException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}

/// Anything the mapper does not recognize; keeps the original text.
final class UnknownDatabaseException extends QueryaDatabaseException {
  const UnknownDatabaseException(
    super.message, {
    super.detailedExplanation,
    super.remediationHint,
    super.originalError,
    super.stackTrace,
  });
}
