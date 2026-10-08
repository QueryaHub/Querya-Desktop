import 'dart:convert';
import 'dart:io';
import 'dart:math';

/// Where the running app tells `querya-mcp` how to reach it.
///
/// Pure `dart:io` (no Flutter) so the stdio shim can import it. The file holds
/// the loopback port and a random token and is readable by the user only.
class McpEndpoint {
  const McpEndpoint({
    required this.port,
    required this.token,
    required this.pid,
    required this.version,
  });

  final int port;
  final String token;
  final int pid;
  final String version;

  /// Overrides the endpoint file location (tests, several app instances).
  static const envOverride = 'QUERYA_MCP_ENDPOINT';

  /// `$XDG_RUNTIME_DIR/querya/mcp-endpoint.json` on Linux (falls back to
  /// `~/.cache/querya`), `~/Library/Caches/Querya` on macOS,
  /// `%LOCALAPPDATA%\Querya` on Windows.
  static File defaultFile([Map<String, String>? environment]) {
    final env = environment ?? Platform.environment;
    final override = env[envOverride];
    if (override != null && override.trim().isNotEmpty) {
      return File(override.trim());
    }
    final sep = Platform.pathSeparator;
    final String dir;
    if (Platform.isWindows) {
      final base = env['LOCALAPPDATA'] ?? '${env['USERPROFILE']}${sep}AppData${sep}Local';
      dir = '$base${sep}Querya';
    } else if (Platform.isMacOS) {
      dir = '${env['HOME']}/Library/Caches/Querya';
    } else {
      final runtime = env['XDG_RUNTIME_DIR'];
      dir = runtime != null && runtime.isNotEmpty
          ? '$runtime/querya'
          : '${env['HOME']}/.cache/querya';
    }
    return File('$dir${sep}mcp-endpoint.json');
  }

  /// 32 random bytes as hex.
  static String newToken() {
    final r = Random.secure();
    return [for (var i = 0; i < 32; i++) r.nextInt(256)]
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Map<String, Object?> toJson() =>
      {'port': port, 'token': token, 'pid': pid, 'version': version};

  static McpEndpoint? tryParse(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final port = m['port'], token = m['token'];
      if (port is! int || token is! String || token.isEmpty) return null;
      return McpEndpoint(
        port: port,
        token: token,
        pid: m['pid'] is int ? m['pid'] as int : 0,
        version: m['version'] is String ? m['version'] as String : '',
      );
    } catch (_) {
      return null;
    }
  }

  static Future<McpEndpoint?> read(File file) async {
    try {
      return tryParse(await file.readAsString());
    } on FileSystemException {
      return null;
    }
  }

  /// Writes atomically with user-only permissions (0700 directory, 0600 file
  /// on Linux / macOS; the Windows per-user profile is already private).
  Future<void> write(File file) async {
    final dir = file.parent;
    await dir.create(recursive: true);
    if (!Platform.isWindows) await _chmod('700', dir.path);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString('');
    if (!Platform.isWindows) await _chmod('600', tmp.path);
    await tmp.writeAsString(jsonEncode(toJson()), flush: true);
    await tmp.rename(file.path);
  }

  static Future<void> _chmod(String mode, String path) async {
    final r = await Process.run('chmod', [mode, path]);
    if (r.exitCode != 0) {
      throw FileSystemException('chmod $mode failed: ${r.stderr}', path);
    }
  }

  /// Constant-time comparison for the handshake token.
  static bool tokensEqual(String a, String b) {
    final x = utf8.encode(a), y = utf8.encode(b);
    var diff = x.length ^ y.length;
    for (var i = 0; i < x.length && i < y.length; i++) {
      diff |= x[i] ^ y[i];
    }
    return diff == 0;
  }
}
