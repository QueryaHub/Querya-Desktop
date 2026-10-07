import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

enum HarnessDiagnosticSeverity { error, warning }

/// A manifest problem with the JSON path it refers to.
final class HarnessDiagnostic {
  const HarnessDiagnostic(this.severity, this.path, this.message);

  final HarnessDiagnosticSeverity severity;

  /// JSON path inside `manifest.json`, e.g. `engines.querya_desktop`.
  final String path;
  final String message;

  bool get isError => severity == HarnessDiagnosticSeverity.error;

  @override
  String toString() => '$path: $message';
}

/// Validates a decoded `manifest.json` of a database-driver extension against
/// the host version in [profile], with a message per problem.
List<HarnessDiagnostic> validateExtensionManifest(
  Object? manifest,
  ExtensionProtocolProfile profile,
) {
  final out = <HarnessDiagnostic>[];
  void error(String path, String message) =>
      out.add(HarnessDiagnostic(HarnessDiagnosticSeverity.error, path, message));
  void warning(String path, String message) => out
      .add(HarnessDiagnostic(HarnessDiagnosticSeverity.warning, path, message));

  if (manifest is! Map) {
    error(r'$', 'manifest.json must contain a JSON object');
    return out;
  }

  String? requireString(String key) {
    final value = manifest[key];
    if (value == null) {
      error(key, 'missing required field');
      return null;
    }
    if (value is! String || value.trim().isEmpty) {
      error(key, 'must be a non-empty string');
      return null;
    }
    return value;
  }

  requireString('id');
  requireString('name');

  final version = manifest['version'];
  if (version == null) {
    warning('version', 'missing; the host falls back to 0.0.0');
  } else if (version is! String || !_semver.hasMatch(version)) {
    error('version', 'must look like x.y.z, got "$version"');
  }

  final type = manifest['type'];
  if (type != 'database_driver') {
    error(
      'type',
      'must be "database_driver" to be tested by this harness, got '
          '${type == null ? 'nothing' : '"$type"'}',
    );
  }

  final main = manifest['main'];
  if (main is! String || main.trim().isEmpty) {
    error('main', 'database drivers must set the executable entry point');
  }

  final engines = manifest['engines'];
  if (engines == null) {
    warning('engines', 'no host version constraint declared');
  } else if (engines is! Map) {
    error('engines', 'must be an object such as {"querya_desktop": "^0.4.11"}');
  } else {
    final range = engines['querya_desktop'];
    if (range is! String) {
      warning('engines.querya_desktop', 'no Querya Desktop constraint declared');
    } else {
      final ok = _satisfies(profile.targetVersion, range);
      if (ok == null) {
        warning('engines.querya_desktop',
            'unsupported range "$range"; use ^x.y.z or >=x.y.z');
      } else if (!ok) {
        warning(
          'engines.querya_desktop',
          'range "$range" does not include target host '
              '${profile.targetVersion}; the host does not enforce this yet, '
              'but the extension declares that it does not support it',
        );
      }
    }
  }

  final sandbox = manifest['sandbox'];
  if (sandbox != null && sandbox is! Map) {
    error('sandbox', 'must be an object');
  }

  final contributions = manifest['contributions'] ?? manifest['contributes'];
  final contributionsKey =
      manifest.containsKey('contributions') ? 'contributions' : 'contributes';
  if (contributions != null && contributions is! Map) {
    error(contributionsKey, 'must be an object');
  } else {
    final drivers = contributions is Map ? contributions['drivers'] : null;
    if (drivers is! List || drivers.isEmpty) {
      error('$contributionsKey.drivers',
          'a database driver must contribute at least one driver');
    } else {
      for (var i = 0; i < drivers.length; i++) {
        final d = drivers[i];
        if (d is! Map) {
          error('$contributionsKey.drivers[$i]', 'must be an object');
          continue;
        }
        for (final key in const ['driverId', 'displayName']) {
          final v = d[key];
          if (v is! String || v.trim().isEmpty) {
            error('$contributionsKey.drivers[$i].$key',
                'missing required field');
          }
        }
      }
    }
    final commands = contributions is Map ? contributions['commands'] : null;
    if (commands is List &&
        commands.isNotEmpty &&
        profile.targetVersion < const HostVersion(0, 4, 16)) {
      warning(
        '$contributionsKey.commands',
        'commands need Querya Desktop 0.4.16 or newer; '
            '${profile.targetVersion} ignores them',
      );
    }
  }

  return out;
}

final _semver = RegExp(r'^\d+\.\d+\.\d+(?:[+-][0-9A-Za-z.+-]+)?$');

/// `true` / `false` when [range] (`^x.y.z` or `>=x.y.z`) can be evaluated,
/// `null` when its syntax is not understood.
bool? _satisfies(HostVersion host, String range) {
  final r = range.trim();
  try {
    if (r.startsWith('>=')) {
      return host >= HostVersion.parse(r.substring(2));
    }
    if (r.startsWith('^')) {
      final base = HostVersion.parse(r.substring(1));
      if (host < base) return false;
      // Caret: same major, or same minor while major is 0.
      return base.major == 0
          ? host.major == 0 && host.minor == base.minor
          : host.major == base.major;
    }
  } on FormatException {
    return null;
  }
  return null;
}
