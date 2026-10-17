import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Whether Querya Desktop runs inside the macOS App Sandbox (#1593).
///
/// The release builds are not sandboxed (#1592), but a debug build
/// (`DebugProfile.entitlements`) and any store-style build are. In the
/// sandbox the app cannot replace its own bundle, start extension processes,
/// let an MCP client outside the sandbox read its endpoint file, or read SSH
/// keys and database files it was not handed: those features then fail
/// without saying why, so they check this and say it.
abstract final class MacOsSandbox {
  static bool? _override;

  /// Forces [isActive] in tests; `null` goes back to detection.
  @visibleForTesting
  static set debugOverride(bool? value) => _override = value;

  /// Whether this process is sandboxed (always false off macOS).
  static bool get isActive =>
      _override ?? (Platform.isMacOS && detect(Platform.environment));

  /// The sandbox sets `APP_SANDBOX_CONTAINER_ID`, and moves `HOME` into the
  /// app's container (`~/Library/Containers/<bundle id>/Data`).
  static bool detect(Map<String, String> environment) {
    final container = environment['APP_SANDBOX_CONTAINER_ID'];
    if (container != null && container.isNotEmpty) return true;
    final home = environment['HOME'] ?? '';
    return home.contains('/Library/Containers/');
  }

  /// One line for a feature that does not work in the sandbox.
  static String unavailable(String feature) =>
      '$feature is not available while Querya Desktop runs in the macOS App '
      'Sandbox (a debug or store-style build). The release build from the '
      'download page is not sandboxed.';
}
