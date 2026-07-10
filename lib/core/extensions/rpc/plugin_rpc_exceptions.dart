/// Thrown when a plugin child process exits unexpectedly (Block C).
class PluginCrashedException implements Exception {
  PluginCrashedException({
    required this.pluginId,
    this.exitCode,
    this.message,
  });

  final String pluginId;
  final int? exitCode;
  final String? message;

  @override
  String toString() {
    final code = exitCode == null ? '' : ' (exitCode=$exitCode)';
    final detail = message == null ? '' : ': $message';
    return 'PluginCrashedException($pluginId)$code$detail';
  }
}

/// Thrown when handshake / shutdown protocol times out.
class PluginProtocolTimeoutException implements Exception {
  PluginProtocolTimeoutException(this.message);
  final String message;

  @override
  String toString() => 'PluginProtocolTimeoutException: $message';
}
