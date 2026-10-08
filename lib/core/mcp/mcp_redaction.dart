import 'package:querya_desktop/core/storage/local_db.dart';

/// Removes credentials from text that goes back to an MCP client.
///
/// Driver errors can quote a connection string or an option list; the model
/// must never see them. Removes the connection's own secrets when they are
/// loaded, then any `scheme://user:password@` user info and
/// `password=...`-style options.
abstract final class McpRedaction {
  static const mask = '***';

  static final _uriUserInfo =
      RegExp(r'([a-zA-Z][a-zA-Z0-9+.\-]*://)[^/@\s]*@');
  static final _keyValue = RegExp(
    r'\b(password|passwd|pwd|passphrase|secret|token|api[_-]?key)(\s*[=:]\s*)'
    r'''("[^"]*"|'[^']*'|[^\s,;&)]+)''',
    caseSensitive: false,
  );
  static final _pemBlock = RegExp(
    r'-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----[\s\S]*?(-----END [A-Z0-9 ]*PRIVATE KEY-----|$)',
  );

  static String redact(String text, {ConnectionRow? row}) {
    var out = text;
    for (final secret in _secretsOf(row)) {
      out = out.replaceAll(secret, mask);
    }
    out = out.replaceAll(_pemBlock, '[private key removed]');
    out = out.replaceAllMapped(_uriUserInfo, (m) => '${m[1]}$mask@');
    out = out.replaceAllMapped(_keyValue, (m) => '${m[1]}${m[2]}$mask');
    return out;
  }

  static Iterable<String> _secretsOf(ConnectionRow? row) sync* {
    if (row == null) return;
    final ssh = row.sshSecrets;
    for (final s in [
      row.connectionString,
      row.password,
      ssh?.password,
      ssh?.passphrase,
      ssh?.jumpPassword,
      ssh?.privateKey,
    ]) {
      // Very short values would mask ordinary words.
      if (s != null && s.length >= 4) yield s;
    }
  }
}
