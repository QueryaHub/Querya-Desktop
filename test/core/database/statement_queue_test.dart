import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:postgres/postgres.dart' show PgException;
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';

/// Records force-closes instead of touching a socket.
class _ProbePostgres extends PostgresConnection {
  _ProbePostgres()
      : super(
          name: 'probe',
          host: 'localhost',
          port: 5432,
          database: 'postgres',
        );

  int forced = 0;

  @override
  Future<void> forceClose() async {
    forced++;
  }
}

class _ProbeMysql extends MysqlConnection {
  _ProbeMysql()
      : super(
          name: 'probe',
          host: 'localhost',
          port: 3306,
          database: 'testdb',
        );

  int forced = 0;

  @override
  Future<void> forceClose() async {
    forced++;
  }
}

void main() {
  group('PostgreSQL statements on one session (#1216)', () {
    test('a server-side cancel is a PgException and keeps the session',
        () async {
      final conn = _ProbePostgres();
      conn.runStatementForTest = (sql, timeout) =>
          Future.error(PgException('canceling statement due to user request'));

      await expectLater(
        conn.execute('SELECT 1'),
        throwsA(isA<PgException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(conn.forced, 0);
    });

    test('a bare TimeoutException closes the session', () async {
      final conn = _ProbePostgres();
      conn.runStatementForTest = (sql, timeout) =>
          Future.error(TimeoutException('driver timer', timeout));

      await expectLater(
        conn.execute('SELECT 1', timeout: const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(conn.forced, 1);
    });

    test('a statement waits for the one before it on the same session',
        () async {
      final conn = _ProbePostgres();
      final log = <String>[];
      final gate = Completer<void>();
      conn.runStatementForTest = (sql, timeout) async {
        log.add('start $sql');
        if (sql == 'A') await gate.future;
        log.add('end $sql');
        throw StateError('no result in this probe');
      };

      final a = conn.execute('A').then<void>((_) {}, onError: (_) {});
      final b = conn.execute('B').then<void>((_) {}, onError: (_) {});
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start A'], reason: 'B must not start while A runs');

      gate.complete();
      await Future.wait([a, b]);
      expect(log, ['start A', 'end A', 'start B', 'end B']);
    });
  });

  group('MySQL statements on one session (#1216)', () {
    test('a statement waits for the one before it on the same session',
        () async {
      final conn = _ProbeMysql();
      final log = <String>[];
      final gate = Completer<void>();
      conn.runStatementForTest = (sql, params, iterable, timeout) async {
        log.add('start $sql');
        if (sql == 'A') await gate.future;
        log.add('end $sql');
        throw StateError('no result in this probe');
      };

      final a = conn.execute('A').then<void>((_) {}, onError: (_) {});
      final b = conn.execute('B').then<void>((_) {}, onError: (_) {});
      await Future<void>.delayed(Duration.zero);
      expect(log, ['start A']);

      gate.complete();
      await Future.wait([a, b]);
      expect(log, ['start A', 'end A', 'start B', 'end B']);
    });

    test('a timed-out statement closes the session it ran on', () async {
      final conn = _ProbeMysql();
      conn.runStatementForTest = (sql, params, iterable, timeout) =>
          Completer<IResultSet>().future;

      await expectLater(
        conn.executeWithTimeout('SELECT SLEEP(100)',
            timeout: const Duration(milliseconds: 20)),
        throwsA(isA<TimeoutException>()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(conn.forced, 1);
    });
  });
}
