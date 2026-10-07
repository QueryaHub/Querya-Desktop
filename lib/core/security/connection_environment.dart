import 'dart:convert';

/// Which kind of server a connection points at. Drives the color coding in the
/// title / status bar and the Safe Mode defaults (see `safe_mode.dart`).
enum ConnectionEnvironment {
  development('development', 'Development', 'DEV'),
  staging('staging', 'Staging', 'STAGING'),
  production('production', 'Production', 'PROD');

  const ConnectionEnvironment(this.storageValue, this.label, this.badge);

  /// Value persisted in the connection's non-secret `driverOptions` JSON.
  final String storageValue;

  /// Name shown in forms.
  final String label;

  /// Short tag shown on the window title bar and status bar.
  final String badge;

  /// Production connections open read-only until the user unlocks them.
  bool get defaultsToReadOnly => this == production;

  /// Key inside `driverOptions`. Prefixed so it cannot collide with a field of
  /// an extension driver's own connection form.
  static const optionsKey = 'querya_environment';

  static ConnectionEnvironment? fromStorageValue(Object? value) {
    if (value is! String) return null;
    for (final e in values) {
      if (e.storageValue == value) return e;
    }
    return null;
  }

  /// Reads the environment out of a `driverOptions` JSON string (null when the
  /// connection is untagged or the JSON is malformed).
  static ConnectionEnvironment? fromDriverOptions(String? driverOptions) {
    if (driverOptions == null || driverOptions.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(driverOptions);
      if (decoded is Map) return fromStorageValue(decoded[optionsKey]);
    } catch (_) {}
    return null;
  }

  /// Returns [driverOptions] with the environment set to [environment] (or
  /// removed when null). Other keys are preserved; returns null when the
  /// result would be empty.
  static String? applyToDriverOptions(
    String? driverOptions,
    ConnectionEnvironment? environment,
  ) {
    var options = <String, dynamic>{};
    if (driverOptions != null && driverOptions.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(driverOptions);
        if (decoded is Map) options = Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    if (environment == null) {
      options.remove(optionsKey);
    } else {
      options[optionsKey] = environment.storageValue;
    }
    return options.isEmpty ? null : jsonEncode(options);
  }
}
