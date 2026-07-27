import 'sandbox_launch_command.dart';

/// Thrown when a process-sandbox driver would launch without OS-level isolation.
class SandboxOsIsolationUnavailableException implements Exception {
  const SandboxOsIsolationUnavailableException({
    required this.platform,
    required this.message,
    this.installHint,
  });

  final String platform;
  final String message;
  final String? installHint;

  @override
  String toString() => 'SandboxOsIsolationUnavailableException: $message';
}

/// Describes why OS sandboxing is unavailable for a launch command.
abstract final class SandboxOsIsolation {
  static SandboxOsIsolationUnavailableException? exceptionForLaunchCommand(
    SandboxLaunchCommand command,
  ) {
    if (command.usesOsSandbox) return null;

    switch (command.platform) {
      case 'linux':
        return const SandboxOsIsolationUnavailableException(
          platform: 'linux',
          message:
              'OS sandbox (bubblewrap) is not available on this Linux system.',
          installHint:
              'Install bubblewrap (bwrap) from your distribution and ensure '
              'unprivileged user namespaces are enabled, or confirm below to '
              'run the driver without OS sandbox.',
        );
      case 'windows':
        return const SandboxOsIsolationUnavailableException(
          platform: 'windows',
          message:
              'Native OS sandbox is not yet available for extension drivers '
              'on Windows.',
          installHint:
              'Drivers run with soft isolation only until AppContainer support '
              'lands. Confirm below only if you trust this extension.',
        );
      default:
        return SandboxOsIsolationUnavailableException(
          platform: command.platform,
          message:
              'OS sandbox is not available for extension drivers on '
              '${command.platform}.',
          installHint:
              'Confirm below only if you trust this extension package.',
        );
    }
  }
}
