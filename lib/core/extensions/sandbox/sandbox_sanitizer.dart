/// Redacts secrets from plugin log lines before they hit disk (Block E §6).
class SandboxSanitizer {
  SandboxSanitizer._();

  static const redactionToken = '[REDACTED BY SANDBOX]';

  /// PEM private key blocks (including RSA / EC / OPENSSH variants).
  static final _privateKey = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z0-9 ]*PRIVATE KEY-----',
    multiLine: true,
  );

  /// Compact JWT (header.payload.signature).
  static final _jwt = RegExp(
    r'\beyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\b',
  );

  /// Connection URIs with an embedded password (`scheme://user:pass@host`).
  static final _uriWithPassword = RegExp(
    r'\b([a-zA-Z][a-zA-Z0-9+.-]*://[^/\s:@]+):([^@\s]+)@',
  );

  /// Common password / token assignment forms in dumps.
  static final _passwordAssignment = RegExp(
    r'''\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token)\b(\s*[:=]\s*)(["']?)([^\s"'&,;]+)(["']?)''',
    caseSensitive: false,
  );

  /// Authorization bearer headers.
  static final _bearer = RegExp(
    r'\b(authorization\s*:\s*bearer\s+)\S+',
    caseSensitive: false,
  );

  /// Sanitizes a single chunk / line of plugin output.
  static String sanitize(String input) {
    if (input.isEmpty) return input;
    var out = input;
    out = out.replaceAll(_privateKey, redactionToken);
    out = out.replaceAll(_jwt, redactionToken);
    out = out.replaceAllMapped(_uriWithPassword, (m) {
      return '${m[1]}:$redactionToken@';
    });
    out = out.replaceAllMapped(_passwordAssignment, (m) {
      final quote = m[3] ?? '';
      final endQuote = m[5] ?? '';
      return '${m[1]}${m[2]}$quote$redactionToken$endQuote';
    });
    out = out.replaceAllMapped(_bearer, (m) {
      return '${m[1]}$redactionToken';
    });
    return out;
  }
}
