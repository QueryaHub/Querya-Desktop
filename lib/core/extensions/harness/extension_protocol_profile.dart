/// A `major.minor.patch` Querya Desktop version (build / pre-release parts of
/// strings such as `0.4.18+2` are ignored).
final class HostVersion implements Comparable<HostVersion> {
  const HostVersion(this.major, this.minor, this.patch);

  /// Parses `x.y.z`, optionally prefixed with `v` and followed by `+build` or
  /// `-pre`. Throws [FormatException] otherwise.
  factory HostVersion.parse(String input) {
    final match = RegExp(r'^v?(\d+)\.(\d+)\.(\d+)(?:[+-].*)?$')
        .firstMatch(input.trim());
    if (match == null) {
      throw FormatException('Not a version (expected x.y.z)', input);
    }
    return HostVersion(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  final int major;
  final int minor;
  final int patch;

  @override
  int compareTo(HostVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >=(HostVersion other) => compareTo(other) >= 0;
  bool operator <(HostVersion other) => compareTo(other) < 0;

  @override
  bool operator ==(Object other) =>
      other is HostVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => '$major.$minor.$patch';
}

/// How strictly the harness treats a missing / failing RPC method.
enum HarnessMethodLevel {
  /// The host cannot use the driver without it; failure fails the run.
  required,

  /// The host falls back gracefully; failure is reported as a warning.
  recommended,
}

/// One JSON-RPC method of the host <-> plugin protocol.
final class HarnessProtocolMethod {
  const HarnessProtocolMethod(this.name, this.since, this.level);

  final String name;

  /// First Querya Desktop release that sends this method.
  final HostVersion since;
  final HarnessMethodLevel level;
}

/// The plugin RPC surface a given Querya Desktop version speaks.
///
/// `since` values come from the first release tag whose sources contain the
/// method. The protocol did not exist before 0.4.11.
final class ExtensionProtocolProfile {
  ExtensionProtocolProfile._(this.targetVersion, this.methods);

  /// Oldest host version with the extension RPC protocol.
  static const minSupported = HostVersion(0, 4, 11);

  static const _all = <HarnessProtocolMethod>[
    HarnessProtocolMethod(
        'system.handshake', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'system.shutdown', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'system.ping', minSupported, HarnessMethodLevel.recommended),
    HarnessProtocolMethod(
        'db.connect', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'db.disconnect', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'db.query', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'db.getSchemaTree', minSupported, HarnessMethodLevel.required),
    HarnessProtocolMethod(
        'db.getCapabilities', minSupported, HarnessMethodLevel.recommended),
    HarnessProtocolMethod(
        'db.getServerStats', minSupported, HarnessMethodLevel.recommended),
    HarnessProtocolMethod(
        'db.getTableSchema', HostVersion(0, 4, 14), HarnessMethodLevel.recommended),
    HarnessProtocolMethod(
        'commands.execute', HostVersion(0, 4, 16), HarnessMethodLevel.recommended),
  ];

  /// Host version this profile emulates.
  final HostVersion targetVersion;

  /// Methods that host version may send.
  final List<HarnessProtocolMethod> methods;

  /// Profile for [target]. Throws [FormatException] for unparsable input and
  /// [ArgumentError] for hosts that predate the protocol.
  factory ExtensionProtocolProfile.forTarget(String target) {
    final version = HostVersion.parse(target);
    if (version < minSupported) {
      throw ArgumentError.value(
        target,
        'target-version',
        'Extensions are not supported before Querya Desktop $minSupported',
      );
    }
    return ExtensionProtocolProfile._(version, [
      for (final m in _all)
        if (version >= m.since) m,
    ]);
  }

  bool supports(String method) => methods.any((m) => m.name == method);

  HarnessMethodLevel? levelOf(String method) {
    for (final m in methods) {
      if (m.name == method) return m.level;
    }
    return null;
  }
}
