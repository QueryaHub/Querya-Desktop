/// Guards against leaking secrets via process argv or environment (Block E §5).
class SandboxSecretGuard {
  SandboxSecretGuard._();

  static final _forbiddenEnvKeys = RegExp(
    r'(password|passwd|secret|token|api[_-]?key|private[_-]?key|credential|connection[_-]?string)',
    caseSensitive: false,
  );

  static final _forbiddenArgFlags = RegExp(
    r'^--?(password|passwd|secret|token|api-?key|private-?key|connection-string)(=|$)',
    caseSensitive: false,
  );

  /// Throws [SandboxSecretLeakException] if [arguments] or [environment]
  /// appear to carry credentials.
  ///
  /// When [knownSecrets] is provided, any exact occurrence of those values in
  /// argv or env values is also rejected.
  static void assertNoSecrets({
    List<String> arguments = const [],
    Map<String, String> environment = const {},
    Iterable<String?> knownSecrets = const [],
  }) {
    final secrets = knownSecrets
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet();

    for (final arg in arguments) {
      if (_forbiddenArgFlags.hasMatch(arg)) {
        throw SandboxSecretLeakException(
          'Refusing to pass credential flag via process arguments: '
          '${_redactArg(arg)}',
        );
      }
      for (final secret in secrets) {
        if (arg.contains(secret)) {
          throw SandboxSecretLeakException(
            'Refusing to pass a known secret value via process arguments.',
          );
        }
      }
    }

    for (final entry in environment.entries) {
      if (_forbiddenEnvKeys.hasMatch(entry.key)) {
        throw SandboxSecretLeakException(
          'Refusing to pass credential via environment variable "${entry.key}".',
        );
      }
      for (final secret in secrets) {
        if (entry.value.contains(secret)) {
          throw SandboxSecretLeakException(
            'Refusing to pass a known secret value via environment '
            '"${entry.key}".',
          );
        }
      }
    }
  }

  static String _redactArg(String arg) {
    final eq = arg.indexOf('=');
    if (eq <= 0) return arg;
    return '${arg.substring(0, eq)}=[REDACTED]';
  }
}

class SandboxSecretLeakException implements Exception {
  SandboxSecretLeakException(this.message);
  final String message;

  @override
  String toString() => 'SandboxSecretLeakException: $message';
}
