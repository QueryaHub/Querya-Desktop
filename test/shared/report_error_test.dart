import 'dart:io';

import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/database_error_mapper.dart';
import 'package:querya_desktop/core/util/querya_log.dart';
import 'package:querya_desktop/shared/report_error.dart';

import '../support/querya_theme_test_shell.dart';

void main() {
  late Directory logDir;

  setUp(() async {
    logDir = await Directory.systemTemp.createTemp('querya_report_error_');
    await QueryaLog.instance.init(logDir);
  });
  tearDown(() => logDir.delete(recursive: true));

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

  testWidgets('reportError shows the toast and writes the log', (tester) async {
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
    await tester.runAsync(QueryaLog.instance.flush);
    final text = await tester.runAsync(
      () => File('${logDir.path}/${QueryaLog.fileName}').readAsString(),
    );
    expect(text, contains('[Somewhere.save] The thing was not saved'));
    expect(text, contains('keychain write failed'));

    await tester.pump(const Duration(seconds: 6));
  });
}
