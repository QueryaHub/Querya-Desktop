import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

enum HarnessCheckStatus { passed, warning, failed, skipped }

/// Outcome of one harness check (a manifest rule set or an RPC round-trip).
final class HarnessCheck {
  const HarnessCheck({
    required this.name,
    required this.status,
    this.duration = Duration.zero,
    this.message,
  });

  final String name;
  final HarnessCheckStatus status;
  final Duration duration;

  /// Why the check failed / warned / was skipped; may span several lines.
  final String? message;
}

/// Results of one harness run, renderable as console text, JUnit XML or TAP.
final class HarnessReport {
  HarnessReport({
    required this.extensionId,
    required this.targetVersion,
    required this.checks,
    required this.totalDuration,
    this.peakRssKb,
  });

  final String extensionId;
  final HostVersion targetVersion;
  final List<HarnessCheck> checks;
  final Duration totalDuration;

  /// Highest resident set size sampled for the plugin process, when the
  /// platform exposes it.
  final int? peakRssKb;

  int _count(HarnessCheckStatus s) => checks.where((c) => c.status == s).length;

  int get passedCount => _count(HarnessCheckStatus.passed);
  int get warningCount => _count(HarnessCheckStatus.warning);
  int get failedCount => _count(HarnessCheckStatus.failed);
  int get skippedCount => _count(HarnessCheckStatus.skipped);

  /// `true` when nothing failed (warnings and skips do not fail a run).
  bool get isSuccess => failedCount == 0;

  /// Human-readable summary, one line per check plus indented details.
  String toConsole({bool color = false}) {
    String paint(String code, String text) =>
        color ? '\x1B[${code}m$text\x1B[0m' : text;
    final b = StringBuffer()
      ..writeln('Extension $extensionId against Querya Desktop $targetVersion');
    for (final c in checks) {
      final (mark, code) = switch (c.status) {
        HarnessCheckStatus.passed => ('PASS', '32'),
        HarnessCheckStatus.warning => ('WARN', '33'),
        HarnessCheckStatus.failed => ('FAIL', '31'),
        HarnessCheckStatus.skipped => ('SKIP', '90'),
      };
      b.writeln('  ${paint(code, mark)} ${c.name} '
          '(${c.duration.inMilliseconds} ms)');
      final msg = c.message;
      if (msg != null && msg.isNotEmpty) {
        for (final line in msg.split('\n')) {
          b.writeln('       $line');
        }
      }
    }
    b.writeln('$passedCount passed, $warningCount warnings, '
        '$failedCount failed, $skippedCount skipped in '
        '${totalDuration.inMilliseconds} ms'
        '${peakRssKb == null ? '' : ', plugin peak RSS ${peakRssKb! ~/ 1024} MiB'}');
    return b.toString();
  }

  /// JUnit XML for GitHub Actions / GitLab CI test reporters.
  String toJUnitXml() {
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<testsuites>')
      ..writeln('  <testsuite name="${_xml('$extensionId @ $targetVersion')}" '
          'tests="${checks.length}" failures="$failedCount" errors="0" '
          'skipped="$skippedCount" '
          'time="${(totalDuration.inMilliseconds / 1000).toStringAsFixed(3)}">');
    for (final c in checks) {
      final time = (c.duration.inMilliseconds / 1000).toStringAsFixed(3);
      final open = '    <testcase classname="${_xml(extensionId)}" '
          'name="${_xml(c.name)}" time="$time"';
      final msg = c.message ?? '';
      switch (c.status) {
        case HarnessCheckStatus.passed:
          b.writeln('$open/>');
        case HarnessCheckStatus.warning:
          b
            ..writeln('$open>')
            ..writeln('      <system-out>${_xml(msg)}</system-out>')
            ..writeln('    </testcase>');
        case HarnessCheckStatus.failed:
          b
            ..writeln('$open>')
            ..writeln('      <failure message="${_xml(msg.split('\n').first)}">'
                '${_xml(msg)}</failure>')
            ..writeln('    </testcase>');
        case HarnessCheckStatus.skipped:
          b
            ..writeln('$open>')
            ..writeln('      <skipped message="${_xml(msg)}"/>')
            ..writeln('    </testcase>');
      }
    }
    b
      ..writeln('  </testsuite>')
      ..writeln('</testsuites>');
    return b.toString();
  }

  /// TAP version 13 output.
  String toTap() {
    final b = StringBuffer()
      ..writeln('TAP version 13')
      ..writeln('1..${checks.length}');
    for (var i = 0; i < checks.length; i++) {
      final c = checks[i];
      final ok = c.status != HarnessCheckStatus.failed;
      final directive =
          c.status == HarnessCheckStatus.skipped ? ' # SKIP ${_oneLine(c.message)}' : '';
      b.writeln('${ok ? 'ok' : 'not ok'} ${i + 1} - ${c.name}$directive');
      if (c.status == HarnessCheckStatus.failed ||
          c.status == HarnessCheckStatus.warning) {
        final msg = c.message;
        if (msg != null && msg.isNotEmpty) {
          b.writeln('  ---');
          b.writeln('  message: |');
          for (final line in msg.split('\n')) {
            b.writeln('    $line');
          }
          b.writeln('  ...');
        }
      }
    }
    return b.toString();
  }
}

String _oneLine(String? s) => (s ?? '').replaceAll('\n', ' ');

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
