import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_bridge.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_exceptions.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';

class _FakeProcess implements Process {
  _FakeProcess()
      : _stdoutController = StreamController<List<int>>.broadcast(),
        _stderrController = StreamController<List<int>>.broadcast(),
        _stdinController = StreamController<List<int>>() {
    stdin = IOSink(_stdinController.sink);
    stdinLines = utf8.decoder
        .bind(_stdinController.stream)
        .transform(const LineSplitter())
        .asBroadcastStream();
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final StreamController<List<int>> _stdinController;
  final _exit = Completer<int>();

  late final Stream<String> stdinLines;

  @override
  int get pid => 99;

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) {
      _exit.complete(signal == ProcessSignal.sigkill ? -9 : 0);
    }
    return true;
  }

  void reply(Map<String, Object?> message) {
    _stdoutController.add(utf8.encode('${jsonEncode(message)}\n'));
  }

  void completeExit([int code = 0]) {
    if (!_exit.isCompleted) _exit.complete(code);
  }
}

void main() {
  late Directory tempBase;

  setUp(() async {
    tempBase = await Directory.systemTemp.createTemp('querya_rpc_bridge_');
  });

  tearDown(() async {
    try {
      if (await tempBase.exists()) {
        await tempBase.delete(recursive: true);
      }
    } on PathNotFoundException {
      // Already cleaned by process dispose races.
    } on FileSystemException {
      // Best-effort cleanup.
    }
  });

  const testManifest = ExtensionManifest(
    id: 'test.rpc-driver',
    name: 'RPC Driver',
    version: '1.0.0',
    publisher: 'Test',
    type: ExtensionType.databaseDriver,
    engines: {'querya_desktop': '*'},
    main: 'bin/driver',
    sandbox: SandboxCapabilities(
      engine: SandboxEngine.process,
      network: NetworkPermission(
        mode: NetworkPermissionMode.connectionHostOnly,
      ),
    ),
  );

  test('start performs handshake and sendRequest works', () async {
    final process = _FakeProcess();
    final sub = process.stdinLines.listen((line) {
      final req = jsonDecode(line) as Map<String, dynamic>;
      final method = req['method'];
      if (method == 'system.handshake') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {
            'protocolVersion': '1.0',
            'capabilities': ['db.connect'],
          },
        });
      } else if (method == 'db.connect') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'ok': true},
        });
      } else if (method == 'system.shutdown') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': null,
        });
        process.completeExit(0);
      }
    });

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
      }) async =>
          process,
    );

    final bridge = PluginRpcBridge(
      processRunner: runner,
      enableWatchdog: false,
      enableStderrPipe: false,
    );

    final handshake = await bridge.start(
      manifest: testManifest,
      pluginExecutable: '/opt/driver',
    );
    expect(handshake, isA<Map>());
    expect((handshake as Map)['protocolVersion'], '1.0');

    final connected = await bridge.connect({'host': 'localhost', 'port': 5432});
    expect(connected, {'ok': true});

    await bridge.shutdown();
    expect(bridge.isStarted, isFalse);
    await sub.cancel();
  });

  test('handshake timeout kills process', () async {
    final process = _FakeProcess();
    // Never reply to handshake.
    final sub = process.stdinLines.listen((_) {});

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
      }) async =>
          process,
    );

    final bridge = PluginRpcBridge(
      processRunner: runner,
      handshakeTimeout: const Duration(milliseconds: 40),
      enableWatchdog: false,
      enableStderrPipe: false,
    );

    await expectLater(
      bridge.start(manifest: testManifest, pluginExecutable: '/opt/driver'),
      throwsA(isA<PluginProtocolTimeoutException>()),
    );
    expect(bridge.isStarted, isFalse);
    await sub.cancel();
  });

  test('unexpected exit fails in-flight requests with PluginCrashedException',
      () async {
    final process = _FakeProcess();
    final sub = process.stdinLines.listen((line) {
      final req = jsonDecode(line) as Map<String, dynamic>;
      if (req['method'] == 'system.handshake') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'ok': true},
        });
      }
      // Leave db.connect hanging until crash.
    });

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
      }) async =>
          process,
    );

    final bridge = PluginRpcBridge(
      processRunner: runner,
      enableWatchdog: false,
      enableStderrPipe: false,
      requestTimeout: const Duration(seconds: 5),
    );

    await bridge.start(manifest: testManifest, pluginExecutable: '/opt/driver');
    final pending = bridge.connect({'host': 'x'});
    await Future<void>.delayed(const Duration(milliseconds: 20));
    process.completeExit(1);

    await expectLater(
      pending,
      throwsA(isA<PluginCrashedException>().having((e) => e.exitCode, 'code', 1)),
    );
    await sub.cancel();
  });

  test('shutdown with enableWatchdog: true sends system.shutdown RPC before killing process',
      () async {
    final process = _FakeProcess();
    var shutdownReceived = false;
    final sub = process.stdinLines.listen((line) {
      final req = jsonDecode(line) as Map<String, dynamic>;
      if (req['method'] == 'system.handshake') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'ok': true},
        });
      } else if (req['method'] == 'system.ping') {
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': 'pong',
        });
      } else if (req['method'] == 'system.shutdown') {
        shutdownReceived = true;
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'ok': true},
        });
        process.completeExit(0);
      }
    });

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
      }) async =>
          process,
    );

    final bridge = PluginRpcBridge(
      processRunner: runner,
      enableWatchdog: true,
      enableStderrPipe: false,
    );

    await bridge.start(manifest: testManifest, pluginExecutable: '/opt/driver');
    await bridge.shutdown();

    expect(shutdownReceived, isTrue);
    expect(bridge.isStarted, isFalse);
    await sub.cancel();
  });
}
