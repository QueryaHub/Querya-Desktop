import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_rotating_log.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_sanitizer.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_security_audit.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_stderr_pipe.dart';

class _FakeProcess implements Process {
  _FakeProcess()
      : _stderrController = StreamController<List<int>>.broadcast() {
    stdin = IOSink(StreamController<List<int>>().sink);
  }

  final StreamController<List<int>> _stderrController;
  final _exit = Completer<int>();

  void emitStderr(String text) {
    _stderrController.add(utf8.encode(text));
  }

  Future<void> closeStderr() => _stderrController.close();

  @override
  int get pid => 7;

  @override
  late final IOSink stdin;

  @override
  Stream<List<int>> get stdout => const Stream.empty();

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    if (!_exit.isCompleted) _exit.complete(0);
    return true;
  }
}

void main() {
  group('SandboxSanitizer', () {
    test('redacts JWT, URI passwords, PEM keys, and assignments', () {
      const jwt =
          'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjMifQ.signature';
      const pem = '''
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7
-----END PRIVATE KEY-----
''';
      final input = [
        'token=$jwt',
        'dsn=postgres://alice:hunter2@db.example:5432/app',
        'password: super-secret',
        'Authorization: Bearer abc.def.ghi',
        pem,
      ].join('\n');

      final out = SandboxSanitizer.sanitize(input);
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('super-secret')));
      expect(out, isNot(contains(jwt)));
      expect(out, isNot(contains('BEGIN PRIVATE KEY')));
      expect(out, contains(SandboxSanitizer.redactionToken));
      expect(out, contains('postgres://alice:${SandboxSanitizer.redactionToken}@'));
    });

    test('leaves benign lines untouched', () {
      const line = 'INFO connected to host=db.example port=5432';
      expect(SandboxSanitizer.sanitize(line), line);
    });
  });

  group('SandboxRotatingLog', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('querya_rotlog_');
    });

    tearDown(() async {
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('rotates when exceeding maxBytes and keeps at most 2 files', () async {
      final file = File(p.join(temp.path, 'plugin.log'));
      final log = SandboxRotatingLog(
        file: file,
        maxBytes: 64,
        maxFiles: 2,
      );

      await log.append('a' * 50);
      await log.append('b' * 50);

      expect(await file.exists(), isTrue);
      final archive = File('${file.path}.1');
      expect(await archive.exists(), isTrue);
      expect(await archive.readAsString(), 'a' * 50);
      expect(await file.readAsString(), 'b' * 50);

      await log.append('c' * 50);
      expect(await archive.readAsString(), 'b' * 50);
      expect(await file.readAsString(), 'c' * 50);
      expect(await File('${file.path}.2').exists(), isFalse);
    });
  });

  group('SandboxSecurityAudit', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('querya_audit_');
      SandboxLogPaths.mockLogsDirectory = temp;
    });

    tearDown(() async {
      SandboxLogPaths.mockLogsDirectory = null;
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('writes tab-separated incidents to security_audit.log', () async {
      final audit = SandboxSecurityAudit();
      await audit.record(
        type: SandboxSecurityEventType.forbiddenNetworkHost,
        pluginId: 'test.driver',
        detail: '169.254.169.254',
        at: DateTime.utc(2026, 7, 10, 12),
      );

      final file = await SandboxLogPaths.securityAuditLogFile();
      final body = await file.readAsString();
      expect(body, contains('forbidden_network_host'));
      expect(body, contains('test.driver'));
      expect(body, contains('169.254.169.254'));
      expect(body, startsWith('2026-07-10T12:00:00.000Z'));
    });
  });

  group('SandboxStderrPipe', () {
    late Directory temp;

    setUp(() async {
      temp = await Directory.systemTemp.createTemp('querya_stderr_');
      SandboxLogPaths.mockLogsDirectory = temp;
    });

    tearDown(() async {
      SandboxLogPaths.mockLogsDirectory = null;
      if (await temp.exists()) await temp.delete(recursive: true);
    });

    test('sanitizes stderr and writes rotating plugin log', () async {
      final process = _FakeProcess();
      final scratch = await SandboxScratchDirectory.create(
        pluginId: 'pipe.driver',
        baseDirectory: temp,
        token: '1',
      );
      final handle = SandboxProcessHandle(
        pluginId: 'pipe.driver',
        process: process,
        scratch: scratch,
        launchCommand: const SandboxLaunchCommand(
          executable: '/bin/true',
          arguments: [],
          platform: 'linux',
          usesOsSandbox: false,
        ),
      );

      final audit = SandboxSecurityAudit();
      final lines = <String>[];
      final pipe = await SandboxStderrPipe.attach(
        handle,
        audit: audit,
        onSanitizedLine: lines.add,
      );

      process.emitStderr('password=leak-me\n');
      process.emitStderr('ok line\n');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await pipe.close();

      expect(lines, hasLength(2));
      expect(lines[0], contains(SandboxSanitizer.redactionToken));
      expect(lines[0], isNot(contains('leak-me')));
      expect(lines[1], 'ok line');

      final logFile = await SandboxLogPaths.pluginLogFile('pipe.driver');
      final body = await logFile.readAsString();
      expect(body, contains(SandboxSanitizer.redactionToken));
      expect(body, contains('ok line'));
      expect(body, isNot(contains('leak-me')));

      final auditBody =
          await (await SandboxLogPaths.securityAuditLogFile()).readAsString();
      expect(auditBody, contains('secret_leak_blocked'));

      await handle.dispose();
    });
  });
}
