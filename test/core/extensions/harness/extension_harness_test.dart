import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/extensions/harness/extension_harness.dart';
import 'package:querya_desktop/core/extensions/harness/extension_harness_report.dart';

typedef _Handler = Object? Function(Map<String, dynamic>? params);

class _RpcError implements Exception {
  _RpcError(this.code, this.message);
  final int code;
  final String message;
}

/// Never answers; used to provoke a request timeout.
const _noReply = Object();

/// In-memory plugin speaking newline-delimited JSON-RPC.
class _FakePlugin implements HarnessPluginProcess {
  _FakePlugin(this.handlers, {this.stderrText = ''}) {
    _stdinController.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_onLine);
    if (stderrText.isNotEmpty) {
      scheduleMicrotask(() => _stderr.add(utf8.encode('$stderrText\n')));
    }
  }

  final Map<String, _Handler> handlers;
  final String stderrText;
  final calls = <String>[];
  final _stdout = StreamController<List<int>>();
  final _stderr = StreamController<List<int>>();
  final _stdinController = StreamController<List<int>>();
  final _exit = Completer<int>();
  late final IOSink _stdin = IOSink(_stdinController);

  void _reply(Map<String, Object?> body) {
    if (_stdout.isClosed) return;
    _stdout.add(utf8.encode('${jsonEncode({'jsonrpc': '2.0', ...body})}\n'));
  }

  void _onLine(String line) {
    final msg = jsonDecode(line) as Map<String, dynamic>;
    final id = msg['id'];
    final method = msg['method'] as String;
    calls.add(method);
    final handler = handlers[method];
    if (handler == null) {
      _reply({
        'id': id,
        'error': {'code': -32601, 'message': 'Method not found'},
      });
      return;
    }
    try {
      final result = handler(msg['params'] as Map<String, dynamic>?);
      if (identical(result, _noReply)) return;
      _reply({'id': id, 'result': result});
      if (method == 'system.shutdown' && !_exit.isCompleted) {
        _exit.complete(0);
      }
    } on _RpcError catch (e) {
      _reply({
        'id': id,
        'error': {'code': e.code, 'message': e.message},
      });
    }
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  int get pid => 4242;

  @override
  String? get sandboxNote => null;

  @override
  Future<void> kill() async {
    if (!_exit.isCompleted) _exit.complete(137);
  }

  @override
  Future<void> dispose() async {
    await kill();
    await _stdout.close();
    await _stderr.close();
  }
}

Map<String, _Handler> _healthy() => {
      'system.handshake': (_) => {'protocolVersion': 1},
      'system.ping': (_) => 'pong',
      'db.connect': (_) => {'serverVersion': '24.1'},
      'db.getCapabilities': (_) => {'supportsTransactions': false},
      'db.getServerStats': (_) => {'uptime': 1},
      'db.getSchemaTree': (_) => {'nodes': <Object?>[]},
      'db.query': (_) => {
            'columns': ['one'],
            'rows': [
              [1],
            ],
          },
      'db.getTableSchema': (_) => {'columns': <Object?>[]},
      'db.disconnect': (_) => null,
      'system.shutdown': (_) => null,
    };

void main() {
  late Directory root;

  Map<String, Object?> manifest() => {
        'id': 'acme.clickhouse',
        'name': 'ClickHouse',
        'version': '1.0.0',
        'type': 'database_driver',
        'main': 'bin/driver',
        'engines': {'querya_desktop': '^0.4.11'},
        'contributions': {
          'drivers': [
            {'driverId': 'clickhouse', 'displayName': 'ClickHouse'},
          ],
        },
      };

  void writeExtension(Map<String, Object?> m, {bool entry = true}) {
    File('${root.path}/manifest.json').writeAsStringSync(jsonEncode(m));
    if (entry) {
      File('${root.path}/bin/driver')
        ..createSync(recursive: true)
        ..writeAsStringSync('#!/bin/sh\n');
    }
  }

  setUp(() => root = Directory.systemTemp.createTempSync('ext_harness_'));
  tearDown(() => root.deleteSync(recursive: true));

  Future<(HarnessReport, _FakePlugin?)> run(
    Map<String, _Handler> handlers, {
    String target = '0.5.0',
    HarnessConnectionOptions connection = const HarnessConnectionOptions(),
    Duration timeout = const Duration(seconds: 2),
    String stderrText = '',
  }) async {
    _FakePlugin? plugin;
    final harness = QueryaExtensionHarness(
      requestTimeout: timeout,
      shutdownTimeout: const Duration(milliseconds: 500),
      launcher: (request) async {
        expect(request.executable, endsWith('bin/driver'));
        return plugin = _FakePlugin(handlers, stderrText: stderrText);
      },
    );
    final report = await harness.run(
      extensionRoot: root.path,
      targetVersion: target,
      connection: connection,
    );
    return (report, plugin);
  }

  HarnessCheck check(HarnessReport r, String name) =>
      r.checks.firstWhere((c) => c.name == name);

  test('a healthy driver passes the whole lifecycle in order', () async {
    writeExtension(manifest());
    final (report, plugin) = await run(_healthy());

    expect(report.isSuccess, isTrue, reason: report.toConsole());
    expect(report.failedCount, 0);
    expect(plugin!.calls, [
      'system.handshake',
      'system.ping',
      'db.connect',
      'db.getCapabilities',
      'db.getServerStats',
      'db.getSchemaTree',
      'db.query',
      'db.disconnect',
      'system.shutdown',
    ]);
    expect(report.totalDuration, lessThan(const Duration(seconds: 2)));
  });

  test('connect options and table schema are forwarded', () async {
    writeExtension(manifest());
    Map<String, dynamic>? connectParams;
    Map<String, dynamic>? tableParams;
    final handlers = _healthy()
      ..['db.connect'] = (p) {
        connectParams = p;
        return {'serverVersion': '1'};
      }
      ..['db.getTableSchema'] = (p) {
        tableParams = p;
        return {'columns': <Object?>[]};
      };
    final (report, _) = await run(
      handlers,
      connection: const HarnessConnectionOptions(
        params: {'host': 'db.local', 'port': 9000},
        database: 'shop',
        tableName: 'orders',
      ),
    );
    expect(report.isSuccess, isTrue, reason: report.toConsole());
    expect(connectParams, containsPair('host', 'db.local'));
    expect(connectParams, containsPair('database', 'shop'));
    expect(tableParams, containsPair('tableName', 'orders'));
  });

  test('methods newer than the target host are skipped', () async {
    writeExtension(manifest());
    final (report, plugin) = await run(
      _healthy(),
      target: '0.4.11',
      connection: const HarnessConnectionOptions(tableName: 'orders'),
    );
    expect(report.isSuccess, isTrue, reason: report.toConsole());
    expect(check(report, 'db.getTableSchema').status,
        HarnessCheckStatus.skipped);
    expect(plugin!.calls, isNot(contains('db.getTableSchema')));
  });

  test('a missing recommended method is only a warning', () async {
    writeExtension(manifest());
    final (report, _) = await run(_healthy()..remove('db.getCapabilities'));
    final c = check(report, 'db.getCapabilities');
    expect(c.status, HarnessCheckStatus.warning);
    expect(c.message, contains('not implemented'));
    expect(report.isSuccess, isTrue);
  });

  test('a missing required method fails, later steps skip, shutdown runs',
      () async {
    writeExtension(manifest());
    final (report, plugin) = await run(_healthy()..remove('db.getSchemaTree'));
    expect(check(report, 'db.getSchemaTree').status, HarnessCheckStatus.failed);
    expect(check(report, 'db.query').status, HarnessCheckStatus.skipped);
    expect(check(report, 'system.shutdown').status, HarnessCheckStatus.passed);
    expect(plugin!.calls.last, 'system.shutdown');
    expect(report.isSuccess, isFalse);
  });

  test('a malformed db.query result is explained', () async {
    writeExtension(manifest());
    final (report, _) = await run(_healthy()..['db.query'] = (_) => 'oops');
    final c = check(report, 'db.query');
    expect(c.status, HarnessCheckStatus.failed);
    expect(c.message, contains('"columns"'));
  });

  test('an RPC error is reported with its message and code', () async {
    writeExtension(manifest());
    final (report, _) = await run(
      _healthy()
        ..['db.connect'] = (_) => throw _RpcError(-32000, 'bad password'),
    );
    final c = check(report, 'db.connect');
    expect(c.status, HarnessCheckStatus.failed);
    expect(c.message, contains('bad password'));
    expect(c.message, contains('-32000'));
  });

  test('an unanswered request times out and includes plugin stderr', () async {
    writeExtension(manifest());
    final (report, _) = await run(
      _healthy()..['system.handshake'] = (_) => _noReply,
      timeout: const Duration(milliseconds: 150),
      stderrText: 'panic: boom',
    );
    final c = check(report, 'system.handshake');
    expect(c.status, HarnessCheckStatus.failed);
    expect(c.message, contains('did not answer within'));
    expect(c.message, contains('panic: boom'));
  });

  test('an invalid manifest fails without starting the plugin', () async {
    writeExtension(manifest()..remove('id'));
    var launched = false;
    final harness = QueryaExtensionHarness(launcher: (_) async {
      launched = true;
      return _FakePlugin(_healthy());
    });
    final report = await harness.run(
      extensionRoot: root.path,
      targetVersion: '0.5.0',
    );
    expect(launched, isFalse);
    final m = check(report, 'manifest');
    expect(m.status, HarnessCheckStatus.failed);
    expect(m.message, contains('id: missing required field'));
    expect(check(report, 'launch').status, HarnessCheckStatus.skipped);
  });

  test('a missing manifest.json is reported', () async {
    final (report, _) = await run(_healthy());
    expect(check(report, 'manifest').message, contains('manifest.json not found'));
    expect(report.isSuccess, isFalse);
  });

  test('broken JSON in manifest.json is reported', () async {
    File('${root.path}/manifest.json').writeAsStringSync('{ nope');
    final (report, _) = await run(_healthy());
    expect(check(report, 'manifest').message, contains('not valid JSON'));
  });

  test('a missing entry point fails the launch step', () async {
    writeExtension(manifest(), entry: false);
    final (report, _) = await run(_healthy());
    final c = check(report, 'launch');
    expect(c.status, HarnessCheckStatus.failed);
    expect(c.message, contains('entry point not found'));
  });

  test('targets older than the protocol are rejected', () {
    writeExtension(manifest());
    expect(
      QueryaExtensionHarness().run(
        extensionRoot: root.path,
        targetVersion: '0.4.10',
      ),
      throwsArgumentError,
    );
  });
}
