import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/updater/installers/update_install_context.dart';
import 'package:querya_desktop/core/updater/installers/update_install_utils.dart';

/// #1587: the macOS replace script runs under `/bin/sh` with an `open` that
/// records what it was asked to open, against bundles in a temp directory.
/// `ditto` is macOS-only, so on Linux the script's `cp -R` path runs.
class _Setup {
  _Setup(this.root);

  final Directory root;

  String get apps => p.join(root.path, 'Applications');
  String get target => p.join(apps, 'Querya.app');
  String get work => p.join(root.path, 'work');
  String get newApp => p.join(work, 'Querya.app');
  String get exe => p.join(target, 'Contents', 'MacOS', 'querya_desktop');
  String get log =>
      p.join(root.path, 'Library', 'Logs', 'Querya', 'querya-update.log');
  File get opened => File(p.join(root.path, 'opened'));

  String contentOf(String bundle) => File(
        p.join(bundle, 'Contents', 'MacOS', 'querya_desktop'),
      ).readAsStringSync();

  static Future<_Setup> create() async {
    final root = await Directory.systemTemp.createTemp('querya_mac_update_');
    final s = _Setup(root);
    for (final (bundle, content) in [(s.target, 'old'), (s.newApp, 'new')]) {
      final exe = File(p.join(bundle, 'Contents', 'MacOS', 'querya_desktop'));
      await exe.create(recursive: true);
      await exe.writeAsString(content);
    }
    final bin = Directory(p.join(root.path, 'bin'))..createSync();
    final open = File(p.join(bin.path, 'open'))
      ..writeAsStringSync('#!/bin/sh\necho "\$1" >> "\$HOME/opened"\n');
    await Process.run('chmod', ['+x', open.path]);
    return s;
  }

  /// Writes and runs the script for a process that has already exited.
  Future<ProcessResult> run() async {
    final done = await Process.start('true', const []);
    await done.exitCode;
    final script = File(p.join(root.path, 'update.sh'))
      ..writeAsStringSync(buildMacAppReplaceScript(
        pid: done.pid,
        newAppBundle: newApp,
        targetAppBundle: target,
        executable: exe,
        workDir: work,
      ));
    return Process.run(
      '/bin/sh',
      [script.path],
      environment: {
        'HOME': root.path,
        'PATH': '${p.join(root.path, 'bin')}:${Platform.environment['PATH']}',
      },
    );
  }
}

bool get _isRoot =>
    (Process.runSync('id', const ['-u']).stdout as String).trim() == '0';

void main() {
  group('buildMacAppReplaceScript (#1587)', () {
    late _Setup s;

    setUp(() async => s = await _Setup.create());
    tearDown(() async {
      await Process.run('chmod', ['-R', 'u+rwx', s.root.path]);
      await s.root.delete(recursive: true);
    });

    test('replaces the bundle, removes .old and the work dir, opens it',
        () async {
      final result = await s.run();

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(s.contentOf(s.target), 'new');
      expect(Directory('${s.target}.old').existsSync(), isFalse);
      expect(Directory(s.work).existsSync(), isFalse);
      expect(File(p.join(s.root.path, 'update.sh')).existsSync(), isFalse);
      expect(s.opened.readAsStringSync().trim(), s.target);
    });

    test('a stale .old from an earlier update does not block it', () async {
      Directory('${s.target}.old').createSync();
      final result = await s.run();
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(s.contentOf(s.target), 'new');
      expect(Directory('${s.target}.old').existsSync(), isFalse);
    });

    test('a failed copy restores the old app, logs and opens it', () async {
      final unreadable = File(p.join(s.newApp, 'Contents', 'secret'))
        ..writeAsStringSync('x');
      await Process.run('chmod', ['000', unreadable.path]);

      final result = await s.run();

      expect(result.exitCode, 1);
      expect(s.contentOf(s.target), 'old');
      expect(Directory('${s.target}.old').existsSync(), isFalse);
      expect(Directory(s.work).existsSync(), isFalse);
      expect(File(s.log).readAsStringSync(), contains('the old one is restored'));
      expect(s.opened.readAsStringSync().trim(), s.target);
    }, skip: _isRoot ? 'root can read a 000 file' : null);

    test('a folder that cannot be written leaves the app as it was',
        () async {
      await Process.run('chmod', ['555', s.apps]);

      final result = await s.run();

      expect(result.exitCode, 1);
      expect(s.contentOf(s.target), 'old');
      expect(File(s.log).readAsStringSync(), contains('could not move'));
      expect(s.opened.readAsStringSync().trim(), s.target);
    }, skip: _isRoot ? 'root can write a 555 folder' : null);

    test('quotes paths with spaces and quotes', () {
      final script = buildMacAppReplaceScript(
        pid: 1,
        newAppBundle: "/tmp/it's new/Querya.app",
        targetAppBundle: '/Applications/Querya Desktop.app',
        executable: '/Applications/Querya Desktop.app/Contents/MacOS/q',
        workDir: "/tmp/it's new",
      );
      expect(script, contains(r"NEW='/tmp/it'\''s new/Querya.app'"));
      expect(script, contains("TARGET='/Applications/Querya Desktop.app'"));
      expect(script, isNot(contains('|| true')));
    });
  }, skip: Platform.isWindows ? 'POSIX shell script' : null);

  group('macAppBundleReplaceProblemFor (#1587)', () {
    UpdateInstallContext context({bool writable = true}) =>
        UpdateInstallContext(
          environment: const {},
          resolvedExecutable: '/Applications/Querya.app/Contents/MacOS/q',
          isDirectoryWritable: (_) => writable,
        );

    test('null for a writable Applications folder', () {
      expect(
        context().macAppBundleReplaceProblemFor('/Applications/Querya.app'),
        isNull,
      );
    });

    test('a translocated copy must be moved first', () {
      expect(
        context().macAppBundleReplaceProblemFor(
          '/private/var/folders/x/T/AppTranslocation/ABC/d/Querya.app',
        ),
        contains('Applications folder'),
      );
    });

    test('a folder this user cannot write, such as a disk image', () {
      expect(
        context(writable: false)
            .macAppBundleReplaceProblemFor('/Volumes/Querya/Querya.app'),
        contains('/Volumes/Querya'),
      );
    });
  });
}
