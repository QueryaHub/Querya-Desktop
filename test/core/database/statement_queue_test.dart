import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:postgres/postgres.dart' show PgException;
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/postgres_connection.dart';
import 'package:querya_desktop/core/database/statement_queue.dart';

/// Records force-closes instead of touching a socket.
class _ProbePostgres extends PostgresConnection {
  _ProbePostgres()
      : super(
          id: 1,
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
          id: 1,
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

  group('PostgreSQL acceptance (#1216)', () {
    test('after a server-side cancel the next statement runs on the session',
        () async {
      final conn = _ProbePostgres();
      final ran = <String>[];
      conn.runStatementForTest = (sql, timeout) {
        ran.add(sql);
        if (sql == 'A') {
          return Future.error(
              PgException('canceling statement due to user request'));
        }
        return Future.error(StateError('no result in this probe'));
      };

      await expectLater(conn.execute('A'), throwsA(isA<PgException>()));
      await expectLater(conn.execute('B'), throwsA(isA<StateError>()));
      expect(ran, ['A', 'B']);
      expect(conn.forced, 0);
    });

    test(
        'a statement longer than the next one\'s timeout is not cancelled; '
        'the next timeout starts with the next statement', () async {
      final conn = _ProbePostgres();
      final log = <String>[];
      final gate = Completer<void>();
      conn.runStatementForTest = (sql, timeout) async {
        log.add('start $sql timeout=${timeout?.inMilliseconds}');
        if (sql == 'A') await gate.future;
        log.add('end $sql');
        throw StateError('done $sql');
      };

      Object? aError;
      final a = conn.execute('A').then<void>((_) {}, onError: (Object e) {
        aError = e;
      });
      final b = conn
          .execute('B', timeout: const Duration(milliseconds: 20))
          .then<void>((_) {}, onError: (_) {});
      // A runs well past B's 20 ms.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(log, ['start A timeout=null']);

      gate.complete();
      await Future.wait([a, b]);
      // A finished on its own: B's timeout did not cancel it, and the driver got
      // B's 20 ms only when B started.
      expect((aError as StateError).message, 'done A');
      expect(log, [
        'start A timeout=null',
        'end A',
        'start B timeout=20',
        'end B',
      ]);
      expect(conn.forced, 0);
    });

    test('a bare TimeoutException closes only the session it ran on',
        () async {
      final broken = _ProbePostgres();
      final other = _ProbePostgres();
      broken.runStatementForTest = (sql, timeout) =>
          Future.error(TimeoutException('driver timer', timeout));
      other.runStatementForTest =
          (sql, timeout) => Future.error(StateError('no result in this probe'));

      await expectLater(
        broken.execute('SELECT 1', timeout: const Duration(seconds: 1)),
        throwsA(isA<TimeoutException>()),
      );
      await expectLater(other.execute('SELECT 1'), throwsA(isA<StateError>()));
      await Future<void>.delayed(Duration.zero);
      expect(broken.forced, 1);
      expect(other.forced, 0);
    });
  });

  group('MySQL acceptance (#1216)', () {
    testWidgets('a query waiting more than 10 s behind another keeps the session',
        (tester) async {
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
      // The client used to give up after 10 s of polling and close the session.
      await tester.pump(const Duration(seconds: 11));
      expect(log, ['start A']);

      gate.complete();
      await tester.pump();
      await Future.wait([a, b]);
      expect(log, ['start A', 'end A', 'start B', 'end B']);
      expect(conn.forced, 0);
    });
  });

  group('StatementQueue', () {
    testWidgets(
        'a statement that waits past the limit fails on its own and does not '
        'run; the running one and the ones after it are untouched',
        (tester) async {
      final queue = StatementQueue(waitLimit: const Duration(minutes: 2));
      final log = <String>[];
      final gate = Completer<void>();

      final a = queue.run(() async {
        log.add('A');
        await gate.future;
        return 'a';
      });
      Object? bError;
      final b = queue.run(() async {
        log.add('B');
        return 'b';
      }).then<void>((_) {}, onError: (Object e) {
        bError = e;
      });

      await tester.pump(const Duration(minutes: 2, seconds: 1));
      await b;
      expect(bError, isA<StatementWaitTimeoutException>());
      expect('$bError', contains('Waited 120 s for the connection'));

      final c = queue.run(() async {
        log.add('C');
        return 'c';
      });
      gate.complete();
      await tester.pump();
      expect(await a, 'a');
      expect(await c, 'c');
      expect(log, ['A', 'C'], reason: 'B gave up and never ran');
    });

    test('zero waits without a limit', () async {
      final queue = StatementQueue(waitLimit: Duration.zero);
      final gate = Completer<void>();
      final a = queue.run(() => gate.future.then((_) => 1));
      final b = queue.run(() async => 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gate.complete();
      expect(await a, 1);
      expect(await b, 2);
    });
  });

  group('timeout texts', () {
    test('a running timeout and a wait timeout read differently', () {
      expect(
        statementTimeoutText(
            TimeoutException('driver', const Duration(seconds: 30))),
        'Query timed out after 30 s',
      );
      expect(
        statementTimeoutText(
            const StatementWaitTimeoutException(Duration(seconds: 120))),
        startsWith('Waited 120 s for the connection'),
      );
      expect(
        statementTimeoutText(TimeoutException('canceling statement')),
        'Query timed out: canceling statement',
      );
      expect(statementTimeoutText(StateError('x')), isNull);
      expect(formatStatementDuration(const Duration(milliseconds: 250)),
          '250 ms');
    });
  });
}
