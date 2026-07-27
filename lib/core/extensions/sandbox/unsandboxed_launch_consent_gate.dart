import 'sandbox_os_isolation.dart';

typedef UnsandboxedLaunchConsentHandler = Future<bool> Function(
  SandboxOsIsolationUnavailableException details,
);

/// App-level hook for explicit user consent before unsandboxed driver launch.
class UnsandboxedLaunchConsentGate {
  UnsandboxedLaunchConsentGate._();

  static final UnsandboxedLaunchConsentGate instance =
      UnsandboxedLaunchConsentGate._();

  UnsandboxedLaunchConsentHandler? handler;

  Future<bool> request(SandboxOsIsolationUnavailableException details) async {
    final callback = handler;
    if (callback == null) return false;
    return callback(details);
  }
}
