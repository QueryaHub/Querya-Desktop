import 'dart:convert';

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

/// One JSON-RPC round trip as the harness saw it: what was sent, how long the
/// plugin took, and a bounded, redacted view of the answer (the trace of
/// `--trace`).
final class HarnessRpcCall {
  const HarnessRpcCall({
    required this.method,
    required this.duration,
    required this.requestBytes,
    required this.ok,
    this.responseBytes,
    this.error,
    this.request,
    this.response,
  });

  final String method;
  final Duration duration;
  final int requestBytes;
  final bool ok;
  final int? responseBytes;
  final String? error;

  /// The request params with secrets replaced by `***`.
  final Object? request;

  /// The result, cut to a few rows and short strings.
  final Object? response;

  Map<String, Object?> toJson() => {
        'method': method,
        'ms': duration.inMilliseconds,
        'ok': ok,
        'requestBytes': requestBytes,
        if (responseBytes != null) 'responseBytes': responseBytes,
        if (error != null) 'error': error,
        if (request != null) 'request': request,
        if (response != null) 'response': response,
      };
}

/// Replaces the values of keys that look like secrets with `***`.
Object? redactRpcValue(Object? value) {
  if (value is Map) {
    return {
      for (final e in value.entries)
        '${e.key}': _isSecretKey('${e.key}') ? '***' : redactRpcValue(e.value),
    };
  }
  if (value is List) return [for (final v in value) redactRpcValue(v)];
  return value;
}

bool _isSecretKey(String key) {
  final k = key.toLowerCase();
  return k.contains('password') ||
      k.contains('passwd') ||
      k.contains('secret') ||
      k.contains('token') ||
      k.contains('passphrase') ||
      k == 'pwd' ||
      k == 'apikey' ||
      k == 'api_key' ||
      k == 'privatekey' ||
      k == 'private_key';
}

/// Cuts [value] for a trace: at most [maxItems] list items, strings of at most
/// [maxString] characters, nesting of at most 5 levels.
Object? boundRpcValue(
  Object? value, {
  int maxItems = 5,
  int maxString = 120,
  int depth = 0,
}) {
  if (value is String) {
    return value.length <= maxString
        ? value
        : '${value.substring(0, maxString)}… (${value.length} chars)';
  }
  if (depth >= 5) return value is Map || value is List ? '…' : value;
  if (value is List) {
    return [
      for (final v in value.take(maxItems))
        boundRpcValue(v, maxItems: maxItems, maxString: maxString, depth: depth + 1),
      if (value.length > maxItems) '… (+${value.length - maxItems} more)',
    ];
  }
  if (value is Map) {
    return {
      for (final e in value.entries)
        '${e.key}': boundRpcValue(e.value,
            maxItems: maxItems, maxString: maxString, depth: depth + 1),
    };
  }
  return value;
}

/// Results of one harness run, renderable as console text, JUnit XML or TAP.
final class HarnessReport {
  HarnessReport({
    required this.extensionId,
    required this.targetVersion,
    required this.checks,
    required this.totalDuration,
    this.peakRssKb,
    this.rpc = const [],
  });

  /// Every RPC round trip of the run, in order.
  final List<HarnessRpcCall> rpc;

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

  /// Like [isSuccess], and with [strict] a warning fails the run as well
  /// (a recommended method that errors, a sandbox that could not be applied).
  bool passes({bool strict = false}) =>
      isSuccess && (!strict || warningCount == 0);

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

  /// The checks and every RPC round trip as JSON (the `--trace` file): what
  /// was asked, how long it took and a bounded view of the data that came
  /// back. Secrets in the requests are redacted.
  String toTraceJson() => const JsonEncoder.withIndent('  ').convert({
        'extension': extensionId,
        'targetVersion': '$targetVersion',
        'success': isSuccess,
        'totalMs': totalDuration.inMilliseconds,
        if (peakRssKb != null) 'pluginPeakRssKb': peakRssKb,
        'checks': [
          for (final c in checks)
            {
              'name': c.name,
              'status': c.status.name,
              'ms': c.duration.inMilliseconds,
              if (c.message != null && c.message!.isNotEmpty)
                'message': c.message,
            },
        ],
        'rpc': [for (final r in rpc) r.toJson()],
      });

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
