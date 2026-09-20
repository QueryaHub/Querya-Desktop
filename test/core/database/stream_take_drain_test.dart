import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/mysql_connection.dart';
import 'package:querya_desktop/core/database/sql_limit.dart';
import 'package:querya_desktop/core/database/stream_take_drain.dart';

void main() {
  group('takeThenDrain', () {
    test('keeps first cap items and drains the rest so the producer can finish',
        () async {
      final controller = StreamController<int>();
      final future = takeThenDrain(controller.stream, 2);

      controller.add(1);
      controller.add(2);
      // Must not throw: cancelling at the cap would make this add fail.
      controller.add(3);
      await controller.close();

      final taken = await future;
      expect(taken.items, [1, 2]);
      expect(taken.truncated, isTrue);
      expect(controller.hasListener, isFalse);
    });

    test('does not mark truncated when the stream ends at the cap', () async {
      final taken = await takeThenDrain(Stream.fromIterable([1, 2]), 2);
      expect(taken.items, [1, 2]);
      expect(taken.truncated, isFalse);
    });

    test('empty stream', () async {
      final taken = await takeThenDrain(const Stream<int>.empty(), 5);
      expect(taken.items, isEmpty);
      expect(taken.truncated, isFalse);
    });

    test('after drain, a following stream can be consumed (next query)',
        () async {
      final first = await takeThenDrain(
        Stream.fromIterable([1, 2, 3]),
        2,
      );
      expect(first.items, [1, 2]);

      final second = await takeThenDrain(
        Stream.fromIterable([99]),
        5000,
      );
      expect(second.items, [99]);
      expect(second.truncated, isFalse);
    });
  });

  group('injectSqlLimit + takeThenDrain (MySQL SELECT cap)', () {
    test('SELECT of N+1 rows with cap N; following SELECT 1 succeeds',
        () async {
      const userSql = 'SELECT n FROM t';
      const cap = 2;
      final executed = injectSqlLimit(userSql, cap);
      expect(executed, contains('LIMIT 2'));

      // Server would send at most [cap] rows after LIMIT injection.
      // Simulate a producer that still has leftover rows (no LIMIT / SHOW).
      final leftover = StreamController<int>();
      final capped = takeThenDrain(leftover.stream, cap);
      leftover
        ..add(1)
        ..add(2)
        ..add(3);
      await leftover.close();
      final taken = await capped;
      expect(taken.items.length, cap);

      final followUp = await takeThenDrain(
        Stream.fromIterable([1]),
        cap,
      );
      expect(followUp.items, [1]);
    });
  });

  group('live MySQL COM_QUERY drain', () {
    test(
      'SELECT of N+1 rows with cap N; following SELECT 1 succeeds on same connection',
      () async {
        final port =
            int.tryParse(Platform.environment['MYSQL_PORT'] ?? '') ?? 3306;
        try {
          final probe = await Socket.connect(
            '127.0.0.1',
            port,
            timeout: const Duration(milliseconds: 200),
          );
          await probe.close();
        } catch (_) {
          markTestSkipped('MySQL is not listening on 127.0.0.1:$port');
          return;
        }

        final conn = MysqlConnection(
          id: 0,
          name: 'live-808',
          host: '127.0.0.1',
          port: port,
          username: Platform.environment['MYSQL_USER'] ?? 'querya',
          password: Platform.environment['MYSQL_PASSWORD'] ?? 'querya',
          database: Platform.environment['MYSQL_DATABASE'] ?? 'querya',
          useSSL: false,
        );
        await conn.connect(connectTimeoutMs: 3000);
        addTearDown(() => conn.disconnect());

        const cap = 2;
        // Unbounded SELECT (no injectSqlLimit) so leftover protocol rows exist.
        final rs = await conn.execute(
          'SELECT 1 AS n UNION ALL SELECT 2 UNION ALL SELECT 3',
          null,
          true,
        );
        final taken = await takeThenDrain(rs.rowsStream, cap);
        expect(taken.items.length, cap);
        expect(taken.truncated, isTrue);

        final one = await conn.execute('SELECT 1 AS x');
        expect(one.rows.first.colAt(0), '1');
      },
    );
  });
}
