import 'dart:async';

/// Statements on one database session, run one at a time in our own layer.
///
/// The drivers do not do this well: `postgres` starts a statement's timeout
/// before the statement gets the connection, so a statement waiting in line
/// could cancel the one running; `mysql_client` polls for the previous
/// statement and gives up after 10 s. Here a statement's own timeout starts
/// when it starts, and waiting has its own limit and its own error (#1216).
class StatementQueue {
  StatementQueue({this.waitLimit = defaultWaitLimit});

  /// How long a statement may wait for the ones before it.
  static const defaultWaitLimit = Duration(minutes: 2);

  /// A statement still waiting after this fails with
  /// [StatementWaitTimeoutException] and never runs; the statement it waited
  /// for is not touched. Zero waits without a limit.
  Duration waitLimit;

  Future<void> _tail = Future<void>.value();

  /// Runs [statement] after every statement queued before it.
  Future<T> run<T>(Future<T> Function() statement) {
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;

    final result = Completer<T>();
    final limit = waitLimit;
    final waitTimer = limit > Duration.zero
        ? Timer(limit, () {
            if (!result.isCompleted) {
              result.completeError(StatementWaitTimeoutException(limit));
            }
          })
        : null;

    unawaited(previous.then((_) async {
      waitTimer?.cancel();
      // Gave up waiting: skip the statement, pass the turn on.
      if (result.isCompleted) {
        turn.complete();
        return;
      }
      try {
        result.complete(await statement());
      } catch (e, st) {
        result.completeError(e, st);
      } finally {
        turn.complete();
      }
    }));
    return result.future;
  }
}

/// A statement waited longer than [limit] for another statement on the same
/// session and did not run. The session is fine: nothing was cancelled.
class StatementWaitTimeoutException implements Exception {
  const StatementWaitTimeoutException(this.limit);

  final Duration limit;

  String get message => 'Waited ${formatStatementDuration(limit)} for the '
      'connection: another statement is still running on it.';

  @override
  String toString() => message;
}

/// What the user reads when a statement timed out: running too long or
/// waiting too long for the session. Null when [error] is neither.
String? statementTimeoutText(Object error) {
  if (error is StatementWaitTimeoutException) return error.message;
  if (error is TimeoutException) {
    final d = error.duration;
    // No duration: a server-side cancel the driver reports as a timeout
    // (PostgreSQL 57014); its message says why.
    return d == null
        ? 'Query timed out: ${error.message ?? error}'
        : 'Query timed out after ${formatStatementDuration(d)}';
  }
  return null;
}

/// `30 s`, or `250 ms` below a whole second.
String formatStatementDuration(Duration d) =>
    d.inMilliseconds % 1000 == 0 ? '${d.inSeconds} s' : '${d.inMilliseconds} ms';
