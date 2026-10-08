import 'package:flutter/material.dart' as material;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/redis_connection.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/redis/redis_cli_workspace.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../support/querya_theme_test_shell.dart';

const _timeout = Timeout(Duration(seconds: 60));

class _Redis extends RedisConnectionTestFake {
  @override
  Future<dynamic> sendCommand(List<dynamic> args) async {
    final op = args.first.toString().toUpperCase();
    if (op == 'PING') {
      sentCommands.add(op);
      return 'PONG';
    }
    if (op == 'GET') {
      sentCommands.add(op);
      return 'hello';
    }
    return super.sendCommand(args);
  }
}

void main() {
  const row = ConnectionRow(
    id: 700,
    name: 'E2E Redis',
    type: 'redis',
    host: '127.0.0.1',
    port: 6379,
    createdAt: '2026-01-01T00:00:00Z',
  );

  Future<_Redis> open(WidgetTester tester) async {
    final redis = _Redis();
    await redis.connect();
    addTearDown(redis.disconnect);
    await tester.binding.setSurfaceSize(const material.Size(1000, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(queryaThemeTestShell(
      child: material.Scaffold(
        body: RedisCliWorkspace(
            connectionRow: row, connection: redis, database: 0),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return redis;
  }

  Future<void> run(WidgetTester tester, String command) async {
    await tester.enterText(find.byType(TextField), command);
    await tester.pump();
    await tester.tap(find.text('Run'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  String input(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField)).controller!.text;

  testWidgets('Up / Down walk through the command history', timeout: _timeout,
      (tester) async {
    await open(tester);
    await run(tester, 'PING');
    await run(tester, 'GET k');
    expect(find.text('PONG'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(input(tester), 'GET k');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(input(tester), 'PING');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(input(tester), 'GET k');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(input(tester), isEmpty, reason: 'back to the unsent draft');
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('Tab completes a unique command name', timeout: _timeout,
      (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'flushal');
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(input(tester).toUpperCase(), startsWith('FLUSHALL'));
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('FLUSHALL needs confirmation and Cancel sends nothing',
      timeout: _timeout, (tester) async {
    final redis = await open(tester);
    await run(tester, 'FLUSHALL');
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Execute Destructive Statement'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(redis.sentCommands, isNot(contains('FLUSHALL')));
    await tester.pump(const Duration(seconds: 6));
  });
}
