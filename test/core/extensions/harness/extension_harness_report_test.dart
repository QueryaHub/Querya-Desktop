import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/harness/extension_harness_report.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

HarnessReport _report() => HarnessReport(
      extensionId: 'acme.db',
      targetVersion: const HostVersion(0, 4, 18),
      totalDuration: const Duration(milliseconds: 1500),
      peakRssKb: 51200,
      checks: const [
        HarnessCheck(
          name: 'system.handshake',
          status: HarnessCheckStatus.passed,
          duration: Duration(milliseconds: 12),
        ),
        HarnessCheck(
          name: 'db.getCapabilities',
          status: HarnessCheckStatus.warning,
          message: 'method not implemented',
        ),
        HarnessCheck(
          name: 'db.query',
          status: HarnessCheckStatus.failed,
          message: 'result must be <object> & "rows"\nsecond line',
        ),
        HarnessCheck(
          name: 'db.getTableSchema',
          status: HarnessCheckStatus.skipped,
          message: 'not sent by 0.4.11',
        ),
      ],
    );

void main() {
  test('counts and success flag', () {
    final r = _report();
    expect(r.passedCount, 1);
    expect(r.warningCount, 1);
    expect(r.failedCount, 1);
    expect(r.skippedCount, 1);
    expect(r.isSuccess, isFalse);
  });

  test('console output lists every check and a summary', () {
    final text = _report().toConsole();
    expect(text, contains('PASS system.handshake (12 ms)'));
    expect(text, contains('WARN db.getCapabilities'));
    expect(text, contains('FAIL db.query'));
    expect(text, contains('SKIP db.getTableSchema'));
    expect(text, contains('1 passed, 1 warnings, 1 failed, 1 skipped'));
    expect(text, contains('plugin peak RSS 50 MiB'));
    expect(text, isNot(contains('\x1B[')));
  });

  test('console output can be colored', () {
    expect(_report().toConsole(color: true), contains('\x1B[31mFAIL'));
  });

  test('JUnit XML has counts and escapes special characters', () {
    final xml = _report().toJUnitXml();
    expect(xml, contains('tests="4" failures="1" errors="0" skipped="1"'));
    expect(xml, contains('<failure message="result must be &lt;object&gt; '
        '&amp; &quot;rows&quot;">'));
    expect(xml, contains('<skipped message="not sent by 0.4.11"/>'));
    expect(xml, contains('<system-out>method not implemented</system-out>'));
  });

  test('TAP output marks failures and skips', () {
    final tap = _report().toTap();
    expect(tap, startsWith('TAP version 13\n1..4\n'));
    expect(tap, contains('ok 1 - system.handshake'));
    expect(tap, contains('not ok 3 - db.query'));
    expect(tap, contains('ok 4 - db.getTableSchema # SKIP not sent by 0.4.11'));
    expect(tap, contains('    second line'));
  });
}
