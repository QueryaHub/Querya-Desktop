import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_rotating_log.dart';

/// Categories recorded in `security_audit.log`.
enum SandboxSecurityEventType {
  filesystemEscape('filesystem_escape'),
  memoryQuotaExceeded('memory_quota_exceeded'),
  forbiddenNetworkHost('forbidden_network_host'),
  secretLeakBlocked('secret_leak_blocked'),
  deadlock('deadlock'),
  other('other');

  const SandboxSecurityEventType(this.value);
  final String value;
}

/// Append-only security audit journal for sandbox policy violations.
class SandboxSecurityAudit {
  SandboxSecurityAudit({SandboxRotatingLog? log}) : _log = log;

  SandboxRotatingLog? _log;

  /// Max size for the audit log (10 MB, keep 2 files).
  static const maxBytes = 10 * 1024 * 1024;

  Future<SandboxRotatingLog> _ensureLog() async {
    final existing = _log;
    if (existing != null) return existing;
    final file = await SandboxLogPaths.securityAuditLogFile();
    return _log = SandboxRotatingLog(
      file: file,
      maxBytes: maxBytes,
      maxFiles: 2,
    );
  }

  Future<void> record({
    required SandboxSecurityEventType type,
    required String pluginId,
    String? detail,
    DateTime? at,
  }) async {
    final timestamp = (at ?? DateTime.now().toUtc()).toIso8601String();
    final line = StringBuffer()
      ..write(timestamp)
      ..write('\t')
      ..write(type.value)
      ..write('\t')
      ..write(pluginId);
    if (detail != null && detail.isNotEmpty) {
      line
        ..write('\t')
        ..write(detail.replaceAll('\n', ' ').replaceAll('\t', ' '));
    }
    final log = await _ensureLog();
    await log.appendLine(line.toString());
  }
}
