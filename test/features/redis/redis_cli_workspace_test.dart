import 'dart:typed_data';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/destructive_sql_detector.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/redis/redis_cli_workspace.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

class _CliTestRedisConnection extends RedisConnectionTestFake {
  _CliTestRedisConnection({this.onCommand});

  final Future<dynamic> Function(List<dynamic> args)? onCommand;

  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    sentCommands.add(args.first.toString().toUpperCase());
    if (onCommand != null) {
      return onCommand!(args);
    }
    final op = args.first.toString().toUpperCase();
    if (op == 'PING') return 'PONG';
    if (op == 'GET') return 'hello-world';
    if (op == 'SELECT') return 'OK';
    return super.sendCommand(args);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseRedisCliCommand', () {
    test('parses simple commands without arguments', () {
      expect(parseRedisCliCommand('PING'), ['PING']);
      expect(parseRedisCliCommand('   INFO   '), ['INFO']);
    });

    test('parses simple command with arguments', () {
      expect(parseRedisCliCommand('GET my_key'), ['GET', 'my_key']);
      expect(
        parseRedisCliCommand('SET foo bar'),
        ['SET', 'foo', 'bar'],
      );
    });

    test('handles multiple spaces between tokens', () {
      expect(
        parseRedisCliCommand('  HSET    myhash    field1    value1   '),
        ['HSET', 'myhash', 'field1', 'value1'],
      );
    });

    test('handles double-quoted strings with spaces', () {
      expect(
        parseRedisCliCommand('SET "my key name" "hello world"'),
        ['SET', 'my key name', 'hello world'],
      );
    });

    test('handles single-quoted strings with spaces', () {
      expect(
        parseRedisCliCommand("HSET 'my hash' 'full name' 'John Doe'"),
        ['HSET', 'my hash', 'full name', 'John Doe'],
      );
    });

    test('handles escaped quotes inside quotes', () {
      expect(
        parseRedisCliCommand(r'SET mykey "hello \"escaped\" world"'),
        ['SET', 'mykey', 'hello "escaped" world'],
      );
    });

    test('handles empty input', () {
      expect(parseRedisCliCommand(''), isEmpty);
      expect(parseRedisCliCommand('    '), isEmpty);
    });
  });

  group('formatRespReply', () {
    test('formats null as (nil)', () {
      expect(formatRespReply(null), '(nil)');
    });

    test('formats integer', () {
      expect(formatRespReply(0), '(integer) 0');
      expect(formatRespReply(42), '(integer) 42');
      expect(formatRespReply(-1), '(integer) -1');
    });

    test('formats boolean as integer', () {
      expect(formatRespReply(true), '(integer) 1');
      expect(formatRespReply(false), '(integer) 0');
    });

    test('formats OK and PONG as simple strings', () {
      expect(formatRespReply('OK'), 'OK');
      expect(formatRespReply('PONG'), 'PONG');
    });

    test('formats arbitrary string with quotes', () {
      expect(formatRespReply('foobar'), '"foobar"');
    });

    test('formats UTF-8 Uint8List bytes', () {
      final bytes = Uint8List.fromList('redis data'.codeUnits);
      expect(formatRespReply(bytes), '"redis data"');
    });

    test('formats empty list as (empty array)', () {
      expect(formatRespReply([]), '(empty array)');
    });

    test('formats flat list as 1-based indexed lines', () {
      final list = ['first', 42, null];
      final res = formatRespReply(list);
      expect(res, '1) "first"\n2) (integer) 42\n3) (nil)');
    });

    test('formats nested list structure', () {
      final nested = [
        ['itemA', 'itemB'],
        'itemC',
      ];
      final res = formatRespReply(nested);
      expect(res, contains('1)'));
      expect(res, contains('"itemA"'));
      expect(res, contains('"itemB"'));
      expect(res, contains('2) "itemC"'));
    });
  });

  group('checkDangerousRedisCommand', () {
    test('detects FLUSHALL as critical destructive command', () {
      final res = checkDangerousRedisCommand(['FLUSHALL'], 0);
      expect(res, isNotNull);
      expect(res!.type, DestructiveSqlType.redisFlushAll);
      expect(res.targetName, 'all databases');
      expect(res.message, contains('FLUSHALL will delete every key'));
    });

    test('detects flushall case-insensitively', () {
      final res = checkDangerousRedisCommand(['flushall', 'async'], 2);
      expect(res, isNotNull);
      expect(res!.type, DestructiveSqlType.redisFlushAll);
    });

    test('detects FLUSHDB for current database', () {
      final res = checkDangerousRedisCommand(['FLUSHDB'], 3);
      expect(res, isNotNull);
      expect(res!.type, DestructiveSqlType.redisFlushDb);
      expect(res.targetName, 'db3');
      expect(res.message, contains('db3'));
    });

    test('detects SHUTDOWN', () {
      final res = checkDangerousRedisCommand(['SHUTDOWN', 'NOSAVE'], 0);
      expect(res, isNotNull);
      expect(res!.type, DestructiveSqlType.redisShutdown);
      expect(res.targetName, 'server');
    });

    test('detects KEYS with wildcard', () {
      final res1 = checkDangerousRedisCommand(['KEYS', '*'], 0);
      expect(res1, isNotNull);
      expect(res1!.type, DestructiveSqlType.redisKeys);
      expect(res1.targetName, '*');

      final res2 = checkDangerousRedisCommand(['KEYS', 'user:*'], 0);
      expect(res2, isNotNull);
      expect(res2!.type, DestructiveSqlType.redisKeys);
      expect(res2.targetName, 'user:*');

      final res3 = checkDangerousRedisCommand(['KEYS', 'user:?'], 0);
      expect(res3, isNotNull);
      expect(res3!.type, DestructiveSqlType.redisKeys);
      expect(res3.targetName, 'user:?');
    });

    test('allows non-destructive and exact KEYS commands', () {
      expect(checkDangerousRedisCommand(['GET', 'mykey'], 0), isNull);
      expect(checkDangerousRedisCommand(['KEYS', 'exact_key'], 0), isNull);
      expect(checkDangerousRedisCommand(['HGETALL', 'myhash'], 0), isNull);
      expect(checkDangerousRedisCommand([], 0), isNull);
    });
  });

  group('DestructiveSqlType metadata for Redis', () {
    test('verifies label, riskLevel, and description for Redis types', () {
      expect(DestructiveSqlType.redisFlushAll.label, 'FLUSHALL');
      expect(DestructiveSqlType.redisFlushAll.riskLevel, 'CRITICAL');
      expect(DestructiveSqlType.redisFlushAll.description,
          contains('all Redis databases'));

      expect(DestructiveSqlType.redisFlushDb.label, 'FLUSHDB');
      expect(DestructiveSqlType.redisFlushDb.riskLevel, 'CRITICAL');
      expect(DestructiveSqlType.redisFlushDb.description,
          contains('current Redis database'));

      expect(DestructiveSqlType.redisShutdown.label, 'SHUTDOWN');
      expect(DestructiveSqlType.redisShutdown.riskLevel, 'CRITICAL');
      expect(DestructiveSqlType.redisShutdown.description,
          contains('Redis server process'));

      expect(DestructiveSqlType.redisKeys.label, 'KEYS *');
      expect(DestructiveSqlType.redisKeys.riskLevel, 'HIGH');
      expect(DestructiveSqlType.redisKeys.description,
          contains('KEYS'));
    });
  });

  group('RedisCliWorkspace Widget', () {
    testWidgets('renders CLI terminal workspace with prompt and banner',
        (tester) async {
      final fake = _CliTestRedisConnection();
      await fake.connect();

      const connRow = ConnectionRow(
        id: 10,
        name: 'Test Redis',
        type: 'redis',
        host: '127.0.0.1',
        port: 6379,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 900,
              height: 700,
              child: RedisCliWorkspace(
                connectionRow: connRow,
                connection: fake,
                database: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Redis CLI Console'), findsOneWidget);
      expect(find.textContaining('127.0.0.1:6379 [db0]'), findsOneWidget);
      expect(find.text('Clear'), findsOneWidget);
      expect(find.text('db0 >'), findsOneWidget);
      expect(find.text('Run'), findsOneWidget);

      await fake.disconnect();
    });

    testWidgets('executes command and displays formatted result with latency',
        (tester) async {
      final fake = _CliTestRedisConnection();
      await fake.connect();

      const connRow = ConnectionRow(
        id: 11,
        name: 'Test Redis',
        type: 'redis',
        host: '127.0.0.1',
        port: 6379,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 900,
              height: 700,
              child: RedisCliWorkspace(
                connectionRow: connRow,
                connection: fake,
                database: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Enter PING
      final inputField = find.byType(TextField);
      expect(inputField, findsOneWidget);
      await tester.enterText(inputField, 'PING');
      await tester.pump();

      // Tap Run button
      final runBtn = find.text('Run');
      await tester.tap(runBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Verify PONG is in the output
      expect(find.text('PONG'), findsOneWidget);
      expect(find.textContaining('ms'), findsWidgets);

      await fake.disconnect();
    });

    testWidgets('handles "help" command locally', (tester) async {
      final fake = _CliTestRedisConnection();
      await fake.connect();

      const connRow = ConnectionRow(
        id: 12,
        name: 'Test Redis',
        type: 'redis',
        host: '127.0.0.1',
        port: 6379,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 900,
              height: 700,
              child: RedisCliWorkspace(
                connectionRow: connRow,
                connection: fake,
                database: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final inputField = find.byType(TextField);
      await tester.enterText(inputField, 'help');
      await tester.pump();

      final runBtn = find.text('Run');
      await tester.tap(runBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Querya Redis CLI Console'), findsOneWidget);

      await fake.disconnect();
    });

    testWidgets('clears output on "Clear" button tap', (tester) async {
      final fake = _CliTestRedisConnection();
      await fake.connect();

      const connRow = ConnectionRow(
        id: 13,
        name: 'Test Redis',
        type: 'redis',
        host: '127.0.0.1',
        port: 6379,
      );

      await tester.pumpWidget(
        queryaThemeTestShell(
          child: material.Scaffold(
            body: material.SizedBox(
              width: 900,
              height: 700,
              child: RedisCliWorkspace(
                connectionRow: connRow,
                connection: fake,
                database: 0,
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Banner is visible initially
      expect(find.textContaining('Connected to Redis'), findsOneWidget);

      // Tap Clear
      final clearBtn = find.text('Clear');
      await tester.tap(clearBtn);
      await tester.pump();

      // Banner should be cleared
      expect(find.textContaining('Connected to Redis'), findsNothing);

      await fake.disconnect();
    });
  });
}
