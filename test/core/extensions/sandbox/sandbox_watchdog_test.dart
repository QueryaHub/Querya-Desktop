import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_auto_recovery.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_watchdog.dart';

class _FakeProcess implements Process {
  _FakeProcess()
      : _stdoutController = StreamController<List<int>>.broadcast(),
        _stdinController = StreamController<List<int>>() {
    stdin = IOSink(_stdinController.sink);
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stdinController;
  final _exit = Completer<int>();
  var killed = false;
  ProcessSignal? lastSignal;

  @override
  int get pid => 4242;

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => const Stream.empty();

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killed = true;
    lastSignal = signal;
    if (!_exit.isCompleted) {
      _exit.complete(signal == ProcessSignal.sigkill ? -9 : 0);
    }
    return true;
  }

  void completeExit([int code = 1]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

Future<SandboxProcessHandle> _handle(
  _FakeProcess process,
  Directory tempBase,
) async {
  final scratch = await SandboxScratchDirectory.create(
    pluginId: 'wd.driver',
    baseDirectory: tempBase,
    token: '1',
  );
  return SandboxProcessHandle(
    pluginId: 'wd.driver',
    process: process,
    scratch: scratch,
    launchCommand: const SandboxLaunchCommand(
      executable: '/bin/true',
      arguments: [],
      platform: 'linux',
      usesOsSandbox: false,
    ),
  );
}

void main() {
  group('SandboxAutoRecovery', () {
    test('returns 1s → 2s → 4s then exhausts', () {
      var now = DateTime(2026, 1, 1, 12);
      final recovery = SandboxAutoRecovery(clock: () => now);

      expect(recovery.recordFailure(), const Duration(seconds: 1));
      expect(recovery.canRetry, isTrue);
      expect(recovery.recordFailure(), const Duration(seconds: 2));
      expect(recovery.canRetry, isTrue);
      expect(recovery.recordFailure(), const Duration(seconds: 4));
      expect(recovery.canRetry, isFalse);
      expect(recovery.recordFailure(), isNull);
      expect(recovery.nextBackoff(), isNull);
    });

    test('prunes failures outside the window', () {
      var now = DateTime(2026, 1, 1, 12);
      final recovery = SandboxAutoRecovery(clock: () => now);

      expect(recovery.recordFailure(), const Duration(seconds: 1));
      now = now.add(const Duration(minutes: 6));
      expect(recovery.recentFailureCount, 0);
      expect(recovery.canRetry, isTrue);
      expect(recovery.recordFailure(), const Duration(seconds: 1));
    });

    test('recordSuccess clears failures', () {
      final recovery = SandboxAutoRecovery();
      recovery.recordFailure();
      recovery.recordFailure();
      recovery.recordSuccess();
      expect(recovery.recentFailureCount, 0);
      expect(recovery.nextBackoff(), const Duration(seconds: 1));
    });
  });

  group('SandboxWatchdog', () {
    late Directory tempBase;

    setUp(() async {
      tempBase = await Directory.systemTemp.createTemp('querya_wd_test_');
    });

    tearDown(() async {
      if (await tempBase.exists()) {
        await tempBase.delete(recursive: true);
      }
    });

    test('successful ping clears recovery failures', () async {
      final process = _FakeProcess();
      final handle = await _handle(process, tempBase);
      final recovery = SandboxAutoRecovery();
      recovery.recordFailure();

      final ping = Completer<Object?>();
      final watchdog = SandboxWatchdog(
        pingInterval: const Duration(milliseconds: 20),
        pongTimeout: const Duration(seconds: 1),
        recovery: recovery,
        ping: () => ping.future,
      );

      watchdog.start(handle);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      ping.complete('pong');
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(recovery.recentFailureCount, 0);
      expect(watchdog.isRunning, isTrue);

      watchdog.stop();
      await handle.dispose();
    });

    test('ping timeout marks deadlock and SIGKILLs process', () async {
      final process = _FakeProcess();
      final handle = await _handle(process, tempBase);
      final recovery = SandboxAutoRecovery();
      final stopped = Completer<SandboxWatchdogStopReason>();

      final watchdog = SandboxWatchdog(
        pingInterval: const Duration(milliseconds: 20),
        pongTimeout: const Duration(milliseconds: 30),
        recovery: recovery,
        onStopped: stopped.complete,
        ping: () => Future.delayed(const Duration(seconds: 5), () => 'pong'),
      );

      watchdog.start(handle);
      final reason = await stopped.future.timeout(const Duration(seconds: 2));

      expect(reason, SandboxWatchdogStopReason.deadlock);
      expect(process.killed, isTrue);
      expect(process.lastSignal, ProcessSignal.sigkill);
      expect(recovery.recentFailureCount, 1);
      expect(watchdog.isRunning, isFalse);

      await handle.dispose();
    });

    test('unexpected process exit records failure and stops', () async {
      final process = _FakeProcess();
      final handle = await _handle(process, tempBase);
      final recovery = SandboxAutoRecovery();
      final stopped = Completer<SandboxWatchdogStopReason>();

      final watchdog = SandboxWatchdog(
        pingInterval: const Duration(hours: 1),
        recovery: recovery,
        onStopped: stopped.complete,
        ping: () async => 'pong',
      );

      watchdog.start(handle);
      process.completeExit(1);
      final reason = await stopped.future.timeout(const Duration(seconds: 2));

      expect(reason, SandboxWatchdogStopReason.processExited);
      expect(recovery.recentFailureCount, 1);

      await handle.dispose();
    });

    test('stop cancels timer without killing process', () async {
      final process = _FakeProcess();
      final handle = await _handle(process, tempBase);
      var pings = 0;

      final watchdog = SandboxWatchdog(
        pingInterval: const Duration(milliseconds: 15),
        pongTimeout: const Duration(seconds: 1),
        ping: () async {
          pings++;
          return 'pong';
        },
      );

      watchdog.start(handle);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final before = pings;
      watchdog.stop();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(pings, before);
      expect(process.killed, isFalse);
      expect(watchdog.lastStopReason, SandboxWatchdogStopReason.stopped);

      await handle.dispose();
    });
  });

  group('SandboxWatchdog.isPong', () {
    test('accepts common result shapes', () {
      expect(SandboxWatchdog.isPong(null), isTrue);
      expect(SandboxWatchdog.isPong('pong'), isTrue);
      expect(SandboxWatchdog.isPong(true), isTrue);
      expect(SandboxWatchdog.isPong({'pong': true}), isTrue);
      expect(SandboxWatchdog.isPong({'status': 'ok'}), isTrue);
    });
  });
}
