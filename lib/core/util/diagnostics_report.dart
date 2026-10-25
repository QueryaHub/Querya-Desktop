/// The text a user pastes into a bug report: what runs where, and the end of
/// the log. The log lines are already redacted by `QueryaLog`.
String buildDiagnosticsReport({
  required String appVersion,
  required String operatingSystem,
  required String operatingSystemVersion,
  required String dartVersion,
  required List<String> logLines,
  DateTime? now,
}) {
  final out = StringBuffer()
    ..writeln('Querya diagnostics')
    ..writeln('Generated: ${(now ?? DateTime.now()).toUtc().toIso8601String()}')
    ..writeln('Version: $appVersion')
    ..writeln('OS: $operatingSystem $operatingSystemVersion')
    ..writeln('Dart: $dartVersion')
    ..writeln()
    ..writeln('Last ${logLines.length} log lines:');
  if (logLines.isEmpty) {
    out.writeln('(the log is empty)');
  } else {
    logLines.forEach(out.writeln);
  }
  return out.toString();
}
