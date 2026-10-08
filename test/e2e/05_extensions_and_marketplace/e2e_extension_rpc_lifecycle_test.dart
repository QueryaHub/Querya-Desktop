import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/harness/extension_harness.dart';
import 'package:querya_desktop/core/extensions/harness/extension_harness_report.dart';

import 'e2e_stub_driver.dart';

const _timeout = Timeout(Duration(seconds: 60));

void main() {
  final skip = stubDriverSkipReason();
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('querya_e2e_rpc_'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a real driver process passes the whole RPC lifecycle in order',
      timeout: _timeout, skip: skip, () async {
    writeStubDriver(root, mode: 'healthy');

    final report = await QueryaExtensionHarness(
      shutdownTimeout: const Duration(seconds: 3),
    ).run(extensionRoot: root.path, targetVersion: '0.5.0');

    expect(report.isSuccess, isTrue, reason: report.toConsole());
    expect(report.failedCount, 0);
    final names = report.checks.map((c) => c.name).toList();
    expect(
      names.where((n) => n.startsWith('system.') || n.startsWith('db.')),
      containsAllInOrder([
        'system.handshake',
        'db.connect',
        'db.getSchemaTree',
        'db.query',
        'db.disconnect',
        'system.shutdown',
      ]),
    );
    expect(
      report.checks.firstWhere((c) => c.name == 'db.query').status,
      HarnessCheckStatus.passed,
    );
  });

  test('a driver that never answers the handshake fails fast and skips the rest',
      timeout: _timeout, skip: skip, () async {
    writeStubDriver(root, mode: 'mute');

    final report = await QueryaExtensionHarness(
      requestTimeout: const Duration(seconds: 1),
      shutdownTimeout: const Duration(milliseconds: 500),
    ).run(extensionRoot: root.path, targetVersion: '0.5.0');

    expect(report.isSuccess, isFalse);
    expect(
      report.checks.firstWhere((c) => c.name == 'system.handshake').status,
      HarnessCheckStatus.failed,
    );
    expect(report.skippedCount, greaterThan(0));
    expect(
      report.checks.firstWhere((c) => c.name == 'db.query').status,
      HarnessCheckStatus.skipped,
    );
  });

  test('a missing entry point is reported as a launch failure',
      timeout: _timeout, () async {
    File(p.join(root.path, 'manifest.json'))
        .writeAsStringSync(jsonEncode(stubManifest()));

    final report = await QueryaExtensionHarness()
        .run(extensionRoot: root.path, targetVersion: '0.5.0');

    expect(report.isSuccess, isFalse);
    expect(
      report.checks.firstWhere((c) => c.name == 'launch').message,
      contains('entry point not found'),
    );
  });
}
