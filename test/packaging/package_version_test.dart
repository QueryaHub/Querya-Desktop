import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `.deb` / `.rpm` versions sort a beta before its final release (#1494).
void main() {
  final skipNonPosix = Platform.isWindows ? 'needs bash' : null;

  String packageVersion(String version) {
    final r = Process.runSync(
      'bash',
      ['scripts/linux/package_version.sh', version],
    );
    expect(r.exitCode, 0, reason: '${r.stderr}');
    return (r.stdout as String).trim();
  }

  bool has(String tool) =>
      Process.runSync('sh', ['-c', 'command -v $tool']).exitCode == 0;

  test('a pre-release gets ~ before its label; a final version is unchanged',
      () {
    expect(packageVersion('0.5.0'), '0.5.0');
    expect(packageVersion('0.5.0-beta.1'), '0.5.0~beta.1');
    expect(packageVersion('0.5.0-rc-2'), '0.5.0~rc.2');
  }, skip: skipNonPosix);

  // Pairs that must sort as given: older first.
  final ordered = [
    ('0.4.19', '0.5.0-beta.1'),
    ('0.5.0-beta.1', '0.5.0-beta.2'),
    ('0.5.0-beta.2', '0.5.0-beta.10'),
    ('0.5.0-beta.2', '0.5.0'),
    ('0.5.0', '0.5.1'),
  ];

  test('dpkg upgrades a beta to the final release', () {
    for (final (older, newer) in ordered) {
      final r = Process.runSync('dpkg', [
        '--compare-versions',
        packageVersion(older),
        'lt',
        packageVersion(newer),
      ]);
      expect(r.exitCode, 0, reason: '$older should sort before $newer');
    }
  }, skip: skipNonPosix ?? (has('dpkg') ? null : 'dpkg is not installed'));

  test('rpm upgrades a beta to the final release', () {
    for (final (older, newer) in ordered) {
      final a = packageVersion(older), b = packageVersion(newer);
      final r = Process.runSync(
        'rpm',
        ['--eval', '%{lua: print(rpm.vercmp("$a", "$b"))}'],
      );
      expect((r.stdout as String).trim(), '-1',
          reason: '$older should sort before $newer');
    }
  }, skip: skipNonPosix ?? (has('rpm') ? null : 'rpm is not installed'));
}
