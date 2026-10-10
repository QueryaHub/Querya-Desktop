import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The .deb maintainer scripts and the .rpm scriptlets refresh the desktop
/// database and icon cache so the launcher shows up right after install (#1057).
void main() {
  final skipNonPosix = Platform.isWindows ? 'needs a POSIX shell' : null;

  late Directory tmp;
  late Directory binDir;
  late File log;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('maintainer_scripts_');
    binDir = Directory(p.join(tmp.path, 'bin'))..createSync();
    log = File(p.join(tmp.path, 'calls.log'));
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void stub(String name) {
    final f = File(p.join(binDir.path, name))
      ..writeAsStringSync('#!/bin/sh\necho "$name \$*" >> "${log.path}"\n');
    Process.runSync('chmod', ['+x', f.path]);
  }

  ProcessResult run(String script, String action) => Process.runSync(
        '/bin/sh',
        [p.join('packaging', 'linux', 'deb', script), action],
        environment: {'PATH': binDir.path},
        includeParentEnvironment: false,
      );

  List<String> calls() =>
      log.existsSync() ? log.readAsLinesSync() : const <String>[];

  group('postinst', () {
    test('refreshes both caches on configure', () {
      stub('update-desktop-database');
      stub('gtk-update-icon-cache');
      final r = run('postinst', 'configure');
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(calls(), [
        'update-desktop-database -q /usr/share/applications',
        'gtk-update-icon-cache -q -t -f /usr/share/icons/hicolor',
      ]);
    }, skip: skipNonPosix);

    test('succeeds when the tools are not installed', () {
      final r = run('postinst', 'configure');
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(calls(), isEmpty);
    }, skip: skipNonPosix);

    test('succeeds when a tool fails', () {
      final failing = File(p.join(binDir.path, 'update-desktop-database'))
        ..writeAsStringSync('#!/bin/sh\nexit 1\n');
      Process.runSync('chmod', ['+x', failing.path]);
      final r = run('postinst', 'configure');
      expect(r.exitCode, 0, reason: '${r.stderr}');
    }, skip: skipNonPosix);

    test('does nothing for unrelated actions such as abort-upgrade', () {
      stub('update-desktop-database');
      stub('gtk-update-icon-cache');
      final r = run('postinst', 'abort-upgrade');
      expect(r.exitCode, 0);
      expect(calls(), isEmpty);
    }, skip: skipNonPosix);
  });

  group('postrm', () {
    test('refreshes both caches on remove and purge', () {
      stub('update-desktop-database');
      stub('gtk-update-icon-cache');
      for (final action in ['remove', 'purge']) {
        log.writeAsStringSync('');
        final r = run('postrm', action);
        expect(r.exitCode, 0, reason: '$action: ${r.stderr}');
        expect(calls(), hasLength(2), reason: action);
      }
    }, skip: skipNonPosix);

    test('does nothing on upgrade', () {
      stub('update-desktop-database');
      stub('gtk-update-icon-cache');
      final r = run('postrm', 'upgrade');
      expect(r.exitCode, 0);
      expect(calls(), isEmpty);
    }, skip: skipNonPosix);
  });

  test('build_deb.sh installs both scripts as executable', () {
    final script = File('scripts/linux/build_deb.sh').readAsStringSync();
    expect(script, contains('packaging/linux/deb/postinst'));
    expect(script, contains('packaging/linux/deb/postrm'));
    expect(script, contains('"\$PKG/DEBIAN/postinst"'));
    expect(script, contains('-m 0755'));
  });

  test('the rpm spec refreshes the caches after install and removal', () {
    final spec = File('packaging/linux/querya-desktop.spec').readAsStringSync();
    expect(spec, contains('%post\n'));
    expect(spec, contains('%postun\n'));
    expect(
      RegExp(r'update-desktop-database[^\n]*\|\| :').allMatches(spec),
      hasLength(2),
    );
    expect(
      RegExp(r'gtk-update-icon-cache[^\n]*\|\| :').allMatches(spec),
      hasLength(2),
    );
    expect(spec.indexOf('%post\n'), lessThan(spec.indexOf('%files')));
    expect(spec.indexOf('%files'), lessThan(spec.indexOf('%changelog')));
  });

  test('deb and rpm package definitions recommend bubblewrap for driver sandbox', () {
    final debScript = File('scripts/linux/build_deb.sh').readAsStringSync();
    expect(debScript, contains('Recommends: libayatana-appindicator3-1, bubblewrap'));

    final spec = File('packaging/linux/querya-desktop.spec').readAsStringSync();
    expect(spec, contains('Recommends:     bubblewrap'));
  });
}
