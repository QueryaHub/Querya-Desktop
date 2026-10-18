import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// scripts/release/check_release.sh and prepare_beta.sh (#1498).
void main() {
  // The scripts are bash; the release runs them on Linux runners.
  if (Platform.isWindows) return;
  late Directory root;

  void write(String version, String changelog) {
    File(p.join(root.path, 'pubspec.yaml'))
        .writeAsStringSync('name: querya_desktop\nversion: $version\n');
    File(p.join(root.path, 'CHANGELOG.md')).writeAsStringSync(changelog);
  }

  ProcessResult run(String script, List<String> args) => Process.runSync(
        'bash',
        ['scripts/release/$script', ...args],
        environment: {'QUERYA_RELEASE_ROOT': root.path},
      );

  const changelog = '# Changelog\n\n## [Unreleased]\n\n### Added\n- Beta thing\n\n'
      '## [0.4.22] - 2026-10-01\n\n- Old\n';

  setUp(() {
    root = Directory.systemTemp.createTempSync('querya_release_');
    Process.runSync('git', ['init', '-q', root.path]);
  });
  tearDown(() => root.deleteSync(recursive: true));

  group('check_release.sh', () {
    test('a prepared beta passes and is announced as a pre-release', () {
      write('0.5.0-beta.1+6', '# Changelog\n\n## [0.5.0-beta.1] - 2026-10-18\n\n- x\n');
      final r = run('check_release.sh', ['0.5.0-beta.1']);
      expect(r.exitCode, 0, reason: '${r.stdout}');
      expect(r.stdout, contains('pre-release'));
      expect(r.stdout, contains('AUR and the APT / DNF repositories are skipped'));
    });

    test('a missing changelog section is named', () {
      write('0.5.0-beta.1+6', changelog);
      final r = run('check_release.sh', ['0.5.0-beta.1']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains("no '## [0.5.0-beta.1]' section"));
    });

    test('a pubspec that does not match the tag fails', () {
      write('0.4.22+5', '## [0.5.0]\n');
      final r = run('check_release.sh', ['v0.5.0']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('pubspec says 0.4.22+5'));
    });

    test('a beta needs a build number', () {
      write('0.5.0-beta.1', '## [0.5.0-beta.1]\n');
      final r = run('check_release.sh', ['0.5.0-beta.1']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('needs a build number'));
    });

    test('a tag that is not SemVer fails', () {
      write('0.5.0+1', '## [0.5.0]\n');
      expect(run('check_release.sh', ['0.5']).exitCode, 1);
      expect(run('check_release.sh', ['0.5.0-beta_1']).exitCode, 1);
    });

    test('an existing tag fails unless --no-tag-check', () {
      write('0.5.0+1', '## [0.5.0]\n');
      Process.runSync('git', ['-C', root.path, 'add', '.']);
      Process.runSync('git', [
        '-C', root.path, '-c', 'user.email=t@t', '-c', 'user.name=t',
        'commit', '-qm', 'x',
      ]);
      Process.runSync('git', ['-C', root.path, 'tag', '0.5.0']);

      final r = run('check_release.sh', ['0.5.0']);
      expect(r.exitCode, 1);
      expect(r.stdout, contains('already exists'));
      expect(run('check_release.sh', ['0.5.0', '--no-tag-check']).exitCode, 0);
    });

    test('a stable tag is announced as latest', () {
      write('0.5.0+9', '## [0.5.0] - 2026-11-01\n');
      final r = run('check_release.sh', ['0.5.0']);
      expect(r.exitCode, 0, reason: '${r.stdout}');
      expect(r.stdout, contains("make it 'latest'"));
    });
  });

  group('prepare_beta.sh', () {
    test('sets the version, turns Unreleased into the beta section, then checks out',
        () {
      write('0.4.22+5', changelog);
      final r = run('prepare_beta.sh', ['0.5.0', '1']);
      expect(r.exitCode, 0, reason: '${r.stderr}');

      expect(File(p.join(root.path, 'pubspec.yaml')).readAsStringSync(),
          contains('version: 0.5.0-beta.1+6'));
      final notes = File(p.join(root.path, 'CHANGELOG.md')).readAsStringSync();
      final unreleased = notes.indexOf('## [Unreleased]');
      final beta = notes.indexOf('## [0.5.0-beta.1]');
      expect(unreleased, isNonNegative);
      expect(beta, greaterThan(unreleased));
      expect(notes.indexOf('- Beta thing'), greaterThan(beta));
      expect(r.stdout, contains('git tag -a 0.5.0-beta.1'));

      expect(run('check_release.sh', ['0.5.0-beta.1']).exitCode, 0);
    });

    test('refuses a section that already exists and bad arguments', () {
      write('0.5.0-beta.1+6', '## [Unreleased]\n\n## [0.5.0-beta.1]\n');
      expect(run('prepare_beta.sh', ['0.5.0', '1']).exitCode, 1);
      expect(run('prepare_beta.sh', ['0.5', '1']).exitCode, 2);
      expect(run('prepare_beta.sh', ['0.5.0', '0']).exitCode, 2);
    });
  });
}
