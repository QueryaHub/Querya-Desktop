import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/util/querya_log.dart';
import 'package:querya_desktop/shared/report_error.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  late Directory logDir;

  /// For the plain tests only: inside `testWidgets` the log's file writes run
  /// in the fake-async zone and would never complete.
  Future<void> startLog() async {
    logDir = await Directory.systemTemp.createTemp('querya_report_error_');
    await QueryaLog.instance.init(logDir);
    addTearDown(() => logDir.delete(recursive: true));
  }

  Future<material.BuildContext> pumpHost(WidgetTester tester) async {
    late material.BuildContext host;
    await tester.pumpWidget(
      queryaThemeTestShell(
        child: material.Builder(
          builder: (context) {
            host = context;
            return const material.SizedBox();
          },
        ),
      ),
    );
    return host;
  }

  test('describeError keeps an unknown error as it is and hides credentials', () {
    expect(describeError(StateError('boom')), 'Bad state: boom');
    expect(
      describeError(StateError('failed for postgresql://admin:hunter22@db/x')),
      isNot(contains('hunter22')),
    );
  });

  test('describeError maps a driver error to plain words', () {
    final text = describeError(
      const SocketException('Connection refused', osError: OSError('', 111)),
      driver: DatabaseDriver.postgres,
    );
    expect(text, contains('Cannot reach the database server'));
  });

  test('failureMessage logs and returns the inline error line', () async {
    await startLog();
    final text = failureMessage(
      'Delete failed',
      StateError('connection reset'),
      where: 'RedisKeysView',
      driver: DatabaseDriver.redis,
    );
    await QueryaLog.instance.flush();

    expect(text, startsWith('Delete failed: '));
    final log =
        await File('${logDir.path}/${QueryaLog.fileName}').readAsString();
    expect(log, contains('[RedisKeysView] Delete failed'));
  });

  testWidgets('reportError shows the toast', (tester) async {
    final host = await pumpHost(tester);

    reportError(
      host,
      StateError('keychain write failed'),
      where: 'Somewhere.save',
      action: 'The thing was not saved',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('The thing was not saved. Bad state: keychain write failed'),
      findsOneWidget,
    );

    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('runReported tells the user when the action fails', (tester) async {
    final host = await pumpHost(tester);

    runReported(
      host,
      () async => throw StateError('disk full'),
      where: 'Somewhere.save',
      failedAction: 'The setting was not saved',
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      find.text('The setting was not saved. Bad state: disk full'),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('runReported is quiet when the action succeeds', (tester) async {
    final host = await pumpHost(tester);
    var ran = false;

    runReported(
      host,
      () async => ran = true,
      where: 'Somewhere.save',
      failedAction: 'The setting was not saved',
    );
    await tester.pump();

    expect(ran, isTrue);
    expect(find.textContaining('not saved'), findsNothing);
  });
}
