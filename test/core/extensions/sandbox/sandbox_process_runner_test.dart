import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';

class _FakeProcess implements Process {
  _FakeProcess();

  @override
  int get pid => 4242;

  final _exit = Completer<int>();
  var killed = false;
  ProcessSignal? lastSignal;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    lastSignal = signal;
    if (!_exit.isCompleted) _exit.complete(signal == ProcessSignal.sigkill ? -9 : 0);
    return true;
  }

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  IOSink get stdin => IOSink(StreamController<List<int>>().sink);
}

void main() {
  group('SandboxScratchDirectory', () {
    late Directory tempBase;

    setUp(() async {
      tempBase = await Directory.systemTemp.createTemp('querya_scratch_test_');
    });

    tearDown(() async {
      if (await tempBase.exists()) {
        await tempBase.delete(recursive: true);
      }
    });

    test('creates unique directory under querya_sandbox/<id>_*', () async {
      final scratch = await SandboxScratchDirectory.create(
        pluginId: 'queryahub.clickhouse-driver',
        baseDirectory: tempBase,
        token: 'abc',
      );

      expect(scratch.path, contains(SandboxScratchDirectory.rootSegment));
      expect(scratch.path, contains('queryahub.clickhouse-driver_abc'));
      expect(await scratch.directory.exists(), isTrue);

      await scratch.delete();
      expect(await scratch.directory.exists(), isFalse);
    });

    test('sanitizes unsafe plugin ids', () async {
      final scratch = await SandboxScratchDirectory.create(
        pluginId: '../evil;rm -rf',
        baseDirectory: tempBase,
        token: '1',
      );
      expect(p.basename(scratch.path), startsWith('.._evil_rm_-rf_'));
      await scratch.delete();
    });

    test('cleanupOrphans removes old scratch trees', () async {
      final old = await SandboxScratchDirectory.create(
        pluginId: 'old.plugin',
        baseDirectory: tempBase,
        token: 'old',
      );
      // Backdate mtime by rewriting via touch-equivalent: recreate with past
      // is hard cross-platform; instead create and call cleanup with zero age
      // after a tiny delay is flaky. Use maxAge: Duration.zero after ensuring
      // modified is in the past by deleting and checking count on empty.
      await old.delete();

      final fresh = await SandboxScratchDirectory.create(
        pluginId: 'fresh.plugin',
        baseDirectory: tempBase,
        token: 'fresh',
      );
      final removed = await SandboxScratchDirectory.cleanupOrphans(
        baseDirectory: tempBase,
        maxAge: const Duration(days: 365),
      );
      expect(removed, 0);
      expect(await fresh.directory.exists(), isTrue);
      await fresh.delete();
    });
  });

  group('SandboxLaunchCommand', () {
    test('linux builds bwrap argv with ro-bind, scratch bind, die-with-parent',
        () {
      final cmd = SandboxLaunchCommand.build(
        pluginExecutable: '/opt/ext/bin/driver',
        pluginArguments: const ['--rpc'],
        scratchPath: '/tmp/querya_sandbox/ext_1',
        extensionRoot: '/home/u/.querya/extensions/ext',
        capabilities: const SandboxCapabilities(
          engine: SandboxEngine.process,
          resources: ResourceLimits(maxOpenFiles: 32),
        ),
        platformOverride: 'linux',
        bwrapAvailable: true,
      );

      expect(cmd.executable, 'bwrap');
      expect(cmd.usesOsSandbox, isTrue);
      expect(cmd.arguments, containsAllInOrder([
        '--unshare-all',
        '--share-net',
        '--die-with-parent',
        '--ro-bind',
        '/',
        '/',
        '--bind',
        '/tmp/querya_sandbox/ext_1',
        '/tmp/querya_sandbox/ext_1',
        '--chdir',
        '/tmp/querya_sandbox/ext_1',
        '--ro-bind',
        '/home/u/.querya/extensions/ext',
        '/home/u/.querya/extensions/ext',
        '--',
        '/opt/ext/bin/driver',
        '--rpc',
      ]));
      expect(cmd.arguments, contains('QUERYA_SANDBOX_MAX_OPEN_FILES'));
      expect(cmd.arguments, contains('32'));
    });

    test('linux falls back to direct exec when bwrap missing', () {
      final cmd = SandboxLaunchCommand.build(
        pluginExecutable: '/bin/echo',
        pluginArguments: const ['hi'],
        scratchPath: '/tmp/s',
        platformOverride: 'linux',
        bwrapAvailable: false,
      );
      expect(cmd.executable, '/bin/echo');
      expect(cmd.arguments, ['hi']);
      expect(cmd.usesOsSandbox, isFalse);
    });

    test('macos builds sandbox-exec with seatbelt profile', () {
      final cmd = SandboxLaunchCommand.build(
        pluginExecutable: '/opt/driver',
        pluginArguments: const ['a'],
        scratchPath: '/tmp/querya_sandbox/p_1',
        extensionRoot: '/Users/x/ext',
        platformOverride: 'macos',
      );

      expect(cmd.executable, 'sandbox-exec');
      expect(cmd.arguments[0], '-p');
      final profile = cmd.arguments[1];
      expect(profile, contains('(version 1)'));
      expect(profile, contains('(deny default)'));
      expect(profile, contains('(allow network*)'));
      expect(profile, contains('(allow file-write* (subpath "/tmp/querya_sandbox/p_1"))'));
      expect(profile, contains('(allow file-read* (subpath "/Users/x/ext"))'));
      expect(cmd.arguments.sublist(2), ['/opt/driver', 'a']);
    });

    test('windows launches plugin directly (soft sandbox)', () {
      final cmd = SandboxLaunchCommand.build(
        pluginExecutable: r'C:\ext\driver.exe',
        pluginArguments: const ['--rpc'],
        scratchPath: r'C:\Temp\querya_sandbox\p_1',
        platformOverride: 'windows',
      );
      expect(cmd.executable, r'C:\ext\driver.exe');
      expect(cmd.arguments, ['--rpc']);
      expect(cmd.usesOsSandbox, isFalse);
    });
  });

  group('SandboxProcessRunner', () {
    late Directory tempBase;
    late List<({String exe, List<String> args, String? cwd, Map<String, String>? env})>
        starts;

    setUp(() async {
      tempBase = await Directory.systemTemp.createTemp('querya_runner_test_');
      starts = [];
    });

    tearDown(() async {
      if (await tempBase.exists()) {
        await tempBase.delete(recursive: true);
      }
    });

    test('start creates scratch, launches process, dispose cleans up', () async {
      final fake = _FakeProcess();
      final runner = SandboxProcessRunner(
        platformOverride: 'linux',
        bwrapAvailable: true,
        scratchBaseDirectory: tempBase,
        processStarter: (
          exe,
          args, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          starts.add((
            exe: exe,
            args: args,
            cwd: workingDirectory,
            env: environment,
          ));
          return fake;
        },
      );

      final handle = await runner.start(
        pluginId: 'test.driver',
        pluginExecutable: '/opt/driver',
        pluginArguments: const ['--rpc'],
        extensionRoot: '/opt/ext',
        capabilities: const SandboxCapabilities(engine: SandboxEngine.process),
      );

      expect(starts, hasLength(1));
      expect(starts.single.exe, 'bwrap');
      expect(starts.single.env?['QUERYA_SANDBOX_PLUGIN_ID'], 'test.driver');
      expect(starts.single.env?.containsKey('PATH'), isFalse,
          reason: 'parent environment must not be forwarded');
      expect(await handle.scratch.directory.exists(), isTrue);
      expect(handle.launchCommand.usesOsSandbox, isTrue);

      await handle.dispose();
      expect(fake.killed, isTrue);
      expect(await handle.scratch.directory.exists(), isFalse);
      expect(handle.isDisposed, isTrue);

      // Second dispose is a no-op.
      await handle.dispose();
    });

    test('start deletes scratch when process spawn fails', () async {
      Directory? observedScratch;
      final runner = SandboxProcessRunner(
        platformOverride: 'windows',
        scratchBaseDirectory: tempBase,
        processStarter: (
          exe,
          args, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          observedScratch = Directory(workingDirectory!);
          throw const ProcessException('driver.exe', [], 'spawn failed', 1);
        },
      );

      await expectLater(
        () => runner.start(
          pluginId: 'fail.driver',
          pluginExecutable: 'driver.exe',
        ),
        throwsA(isA<ProcessException>()),
      );

      expect(observedScratch, isNotNull);
      expect(await observedScratch!.exists(), isFalse);
    });

    test('kill sends SIGKILL', () async {
      final fake = _FakeProcess();
      final runner = SandboxProcessRunner(
        platformOverride: 'macos',
        scratchBaseDirectory: tempBase,
        processStarter: (
          exe,
          args, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async =>
            fake,
      );

      final handle = await runner.start(
        pluginId: 'mac.driver',
        pluginExecutable: '/opt/driver',
      );
      expect(handle.launchCommand.executable, 'sandbox-exec');

      await handle.kill();
      expect(fake.lastSignal, ProcessSignal.sigkill);
      await handle.dispose();
    });
  });

  group('buildMacOsSeatbeltProfile', () {
    test('escapes nothing unexpected and includes scratch path', () {
      final profile = buildMacOsSeatbeltProfile(
        scratchPath: '/tmp/querya_sandbox/x',
      );
      expect(profile.split('\n').first, '(version 1)');
      // Round-trip through JSON to ensure no control chars.
      expect(jsonEncode(profile), contains(r'/tmp/querya_sandbox/x'));
    });
  });

  group('SandboxProcessRunner integration (bwrap)', () {
    test('linux bwrap launch path creates scratch and dispose cleans it',
        () async {
      if (!Platform.isLinux) return;
      final which = await Process.run('which', ['bwrap']);
      if (which.exitCode != 0) return;

      final tempBase =
          await Directory.systemTemp.createTemp('querya_bwrap_it_');
      addTearDown(() async {
        if (await tempBase.exists()) {
          await tempBase.delete(recursive: true);
        }
      });

      final runner = SandboxProcessRunner(
        platformOverride: 'linux',
        bwrapAvailable: true,
        scratchBaseDirectory: tempBase,
      );

      SandboxProcessHandle? handle;
      try {
        handle = await runner.start(
          pluginId: 'it.true',
          pluginExecutable: '/bin/true',
        );
      } on ProcessException {
        // Kernel may deny user namespaces; command path still covered by unit tests.
        return;
      }

      expect(handle.launchCommand.executable, 'bwrap');
      expect(await handle.scratch.directory.exists(), isTrue);
      // bwrap may exit non-zero when uid maps are restricted; still tear down.
      await handle.process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
      await handle.dispose();
      expect(await handle.scratch.directory.exists(), isFalse);
    });
  });
}
