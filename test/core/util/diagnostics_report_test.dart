import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/util/diagnostics_report.dart';

void main() {
  test('the report names the version, the OS and carries the log lines', () {
    final text = buildDiagnosticsReport(
      appVersion: '0.5.0+7',
      operatingSystem: 'linux',
      operatingSystemVersion: '6.1',
      dartVersion: '3.9.0',
      logLines: ['a', 'b'],
      now: DateTime.utc(2026, 10, 25, 12),
    );

    expect(text, contains('Version: 0.5.0+7'));
    expect(text, contains('OS: linux 6.1'));
    expect(text, contains('Generated: 2026-10-25T12:00:00.000Z'));
    expect(text, contains('Last 2 log lines:\na\nb\n'));
  });

  test('an empty log is said so', () {
    final text = buildDiagnosticsReport(
      appVersion: '1',
      operatingSystem: 'linux',
      operatingSystemVersion: '',
      dartVersion: '3',
      logLines: const [],
    );
    expect(text, contains('(the log is empty)'));
  });
}
