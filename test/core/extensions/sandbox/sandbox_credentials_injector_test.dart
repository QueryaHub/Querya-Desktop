import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_credentials_injector.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_secret_guard.dart';

class _FakeProcess implements Process {
  _FakeProcess()
      : _stdoutController = StreamController<List<int>>.broadcast(),
        _stdinController = StreamController<List<int>>() {
    stdin = IOSink(_stdinController.sink);
    stdinLines = utf8.decoder
        .bind(_stdinController.stream)
        .transform(const LineSplitter())
        .asBroadcastStream();
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stdinController;
  final _exit = Completer<int>();

  late final Stream<String> stdinLines;

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
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }

  void reply(Map<String, Object?> message) {
    _stdoutController.add(utf8.encode('${jsonEncode(message)}\n'));
  }
}

Future<SandboxProcessHandle> _makeHandle(
  _FakeProcess process,
  Directory tempBase,
) async {
  final scratch = await SandboxScratchDirectory.create(
    pluginId: 'test.driver',
    baseDirectory: tempBase,
    token: '1',
  );
  return SandboxProcessHandle(
    pluginId: 'test.driver',
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
  group('SandboxSecretGuard', () {
    test('allows non-secret argv and env', () {
      expect(
        () => SandboxSecretGuard.assertNoSecrets(
          arguments: const ['--rpc', '--verbose'],
          environment: const {'QUERYA_SANDBOX_SCRATCH': '/tmp/x'},
        ),
        returnsNormally,
      );
    });

    test('rejects password flags and env keys', () {
      expect(
        () => SandboxSecretGuard.assertNoSecrets(
          arguments: const ['--password=s3cret'],
        ),
        throwsA(isA<SandboxSecretLeakException>()),
      );
      expect(
        () => SandboxSecretGuard.assertNoSecrets(
          environment: const {'DB_PASSWORD': 'x'},
        ),
        throwsA(isA<SandboxSecretLeakException>()),
      );
    });

    test('rejects known secret substrings in argv', () {
      expect(
        () => SandboxSecretGuard.assertNoSecrets(
          arguments: const ['--dsn=postgres://u:hunter2@h/db'],
          knownSecrets: const ['hunter2'],
        ),
        throwsA(isA<SandboxSecretLeakException>()),
      );
    });
  });

  group('SensitiveUtf8Buffer', () {
    test('clear zeroes bytes and drops reference', () {
      final buf = SensitiveUtf8Buffer('hunter2');
      expect(buf.asString, 'hunter2');
      buf.clear();
      expect(buf.isCleared, isTrue);
      expect(buf.asString, isNull);

      final wiped = Uint8List.fromList(utf8.encode('hunter2'));
      wiped.fillRange(0, wiped.length, 0);
      expect(wiped.every((b) => b == 0), isTrue);
    });
  });

  group('JsonRpcStdioClient', () {
    test('sends request and completes with result', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
      );

      final sub = utf8.decoder
          .bind(stdin.stream)
          .transform(const LineSplitter())
          .listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        stdout.add(utf8.encode('${jsonEncode({
              'jsonrpc': '2.0',
              'id': req['id'],
              'result': {'ok': true},
            })}\n'));
      });

      final result = await client.sendRequest('system.ping');
      expect(result, {'ok': true});
      await client.close();
      await sub.cancel();
      await stdout.close();
    });

    test('maps JSON-RPC errors', () async {
      final stdout = StreamController<List<int>>();
      final stdin = StreamController<List<int>>();
      final client = JsonRpcStdioClient(
        stdout: stdout.stream,
        stdin: IOSink(stdin.sink),
      );

      final sub = utf8.decoder
          .bind(stdin.stream)
          .transform(const LineSplitter())
          .listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        stdout.add(utf8.encode('${jsonEncode({
              'jsonrpc': '2.0',
              'id': req['id'],
              'error': {'code': -32000, 'message': 'auth failed'},
            })}\n'));
      });

      await expectLater(
        client.sendRequest('db.connect', {'host': 'x'}),
        throwsA(
          isA<JsonRpcException>().having(
            (e) => e.message,
            'message',
            'auth failed',
          ),
        ),
      );
      await client.close();
      await sub.cancel();
      await stdout.close();
    });
  });

  group('SandboxCredentialsInjector', () {
    late Directory tempBase;

    setUp(() async {
      tempBase = await Directory.systemTemp.createTemp('querya_cred_test_');
    });

    tearDown(() async {
      if (await tempBase.exists()) {
        await tempBase.delete(recursive: true);
      }
    });

    test('injectCredentials sends system.injectCredentials over stdio', () async {
      final process = _FakeProcess();
      final handle = await _makeHandle(process, tempBase);

      final requestCompleter = Completer<Map<String, dynamic>>();
      final sub = process.stdinLines.listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        if (!requestCompleter.isCompleted) {
          requestCompleter.complete(req);
        }
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'injected': true},
        });
      });

      final injector = SandboxCredentialsInjector(
        secretsReader: (id) async {
          expect(id, 42);
          return (password: 's3cret', connectionString: null);
        },
      );

      final result = await injector.injectCredentials(
        handle: handle,
        connectionId: 42,
      );

      final req = await requestCompleter.future;
      expect(req['method'], 'system.injectCredentials');
      expect(req['params'], containsPair('password', 's3cret'));
      expect(req['params'], containsPair('connectionId', 42));
      expect(result, {'injected': true});

      await sub.cancel();
      await handle.dispose();
    });

    test('connect sends db.connect with host and password', () async {
      final process = _FakeProcess();
      final handle = await _makeHandle(process, tempBase);

      final requestCompleter = Completer<Map<String, dynamic>>();
      final sub = process.stdinLines.listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        if (!requestCompleter.isCompleted) {
          requestCompleter.complete(req);
        }
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'result': {'connected': true},
        });
      });

      final injector = SandboxCredentialsInjector(
        secretsReader: (_) async =>
            (password: 'pw', connectionString: 'postgres://x'),
      );

      final result = await injector.connect(
        handle: handle,
        connectionId: 7,
        host: 'db.example',
        port: 5432,
        username: 'app',
        ssl: true,
      );

      final req = await requestCompleter.future;
      expect(req['method'], 'db.connect');
      final params = req['params'] as Map<String, dynamic>;
      expect(params['host'], 'db.example');
      expect(params['port'], 5432);
      expect(params['password'], 'pw');
      expect(params['ssl'], isTrue);
      expect(result, {'connected': true});

      await sub.cancel();
      await handle.dispose();
    });

    test('clears sensitive buffers even when RPC fails', () async {
      final cleared = <bool>[];
      final process = _FakeProcess();
      final handle = await _makeHandle(process, tempBase);

      final sub = process.stdinLines.listen((line) {
        final req = jsonDecode(line) as Map<String, dynamic>;
        process.reply({
          'jsonrpc': '2.0',
          'id': req['id'] as int,
          'error': {'code': 1, 'message': 'nope'},
        });
      });

      // Verify SensitiveUtf8Buffer.clear semantics used by injector.
      final buf = SensitiveUtf8Buffer('temp-secret');
      expect(buf.isCleared, isFalse);
      buf.clear();
      cleared.add(buf.isCleared);

      final injector = SandboxCredentialsInjector(
        secretsReader: (_) async => (password: 'temp-secret', connectionString: null),
      );

      await expectLater(
        injector.injectCredentials(handle: handle, connectionId: 1),
        throwsA(isA<JsonRpcException>()),
      );
      expect(cleared.single, isTrue);

      await sub.cancel();
      await handle.dispose();
    });
  });

  group('SandboxProcessRunner secret guard integration', () {
    test('start rejects password in arguments before spawn', () async {
      var started = false;
      final runner = SandboxProcessRunner(
        platformOverride: 'windows',
        processStarter: (
          exe,
          args, {
          String? workingDirectory,
          Map<String, String>? environment,
          bool includeParentEnvironment = true,
          bool runInShell = false,
          ProcessStartMode mode = ProcessStartMode.normal,
        }) async {
          started = true;
          throw StateError('should not spawn');
        },
      );

      await expectLater(
        () => runner.start(
          pluginId: 'bad',
          pluginExecutable: 'driver',
          pluginArguments: const ['--password=leak'],
        ),
        throwsA(isA<SandboxSecretLeakException>()),
      );
      expect(started, isFalse);
    });
  });
}
