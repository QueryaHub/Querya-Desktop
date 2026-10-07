import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/harness/extension_harness_report.dart';
import 'package:querya_desktop/core/extensions/harness/extension_manifest_validator.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';

/// How to start the plugin process.
final class HarnessLaunchRequest {
  const HarnessLaunchRequest({
    required this.pluginId,
    required this.executable,
    required this.extensionRoot,
    this.arguments = const [],
    this.sandbox = false,
  });

  final String pluginId;
  final String executable;
  final String extensionRoot;
  final List<String> arguments;

  /// Wrap the plugin in the OS sandbox (`bwrap` / `sandbox-exec`) when possible.
  final bool sandbox;
}

/// A running plugin, abstracted so tests can use an in-memory fake.
abstract interface class HarnessPluginProcess {
  Stream<List<int>> get stdout;
  IOSink get stdin;
  Stream<List<int>> get stderr;
  Future<int> get exitCode;
  int get pid;

  /// Set when sandboxing was requested but could not be applied.
  String? get sandboxNote;

  Future<void> kill();
  Future<void> dispose();
}

typedef HarnessLauncher = Future<HarnessPluginProcess> Function(
  HarnessLaunchRequest request,
);

/// Starts real OS processes, optionally inside the Querya sandbox command.
Future<HarnessPluginProcess> launchPluginProcess(
  HarnessLaunchRequest request,
) async {
  SandboxScratchDirectory? scratch;
  var executable = request.executable;
  var arguments = request.arguments;
  String? note;
  final environment = <String, String>{};

  if (request.sandbox) {
    scratch = await SandboxScratchDirectory.create(pluginId: request.pluginId);
    final command = SandboxLaunchCommand.build(
      pluginExecutable: request.executable,
      pluginArguments: request.arguments,
      scratchPath: scratch.path,
      extensionRoot: request.extensionRoot,
      bwrapAvailable: await _bwrapUsable(),
    );
    executable = command.executable;
    arguments = command.arguments;
    environment['QUERYA_SANDBOX_SCRATCH'] = scratch.path;
    environment['QUERYA_SANDBOX_PLUGIN_ID'] = request.pluginId;
    if (!command.usesOsSandbox) {
      note = 'OS sandbox is not available on ${command.platform}; '
          'the plugin ran without isolation';
    }
  }

  try {
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: scratch?.path ?? request.extensionRoot,
      environment: environment,
    );
    return _OsPluginProcess(process, scratch, note);
  } catch (_) {
    await scratch?.delete();
    rethrow;
  }
}

Future<bool> _bwrapUsable() async {
  if (!Platform.isLinux) return false;
  try {
    final probe = await Process.run(
      'bwrap',
      const ['--ro-bind', '/', '/', '/bin/true'],
    );
    return probe.exitCode == 0;
  } catch (_) {
    return false;
  }
}

final class _OsPluginProcess implements HarnessPluginProcess {
  _OsPluginProcess(this._process, this._scratch, this.sandboxNote);

  final Process _process;
  final SandboxScratchDirectory? _scratch;

  @override
  final String? sandboxNote;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  IOSink get stdin => _process.stdin;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  int get pid => _process.pid;

  @override
  Future<void> kill() async {
    _process.kill(ProcessSignal.sigkill);
    try {
      await _process.exitCode.timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    await kill();
    await _scratch?.delete();
  }
}

/// Parameters for the `db.connect` step; credentials are only ever sent in the
/// RPC payload, never via argv or environment.
final class HarnessConnectionOptions {
  const HarnessConnectionOptions({
    this.params = const {},
    this.query = 'SELECT 1',
    this.tableName,
    this.database,
  });

  /// Extra `db.connect` fields (`host`, `port`, `username`, `password`, ...).
  final Map<String, Object?> params;

  /// Statement for the `db.query` step.
  final String query;

  /// When set, `db.getTableSchema` is exercised for this table.
  final String? tableName;
  final String? database;
}

/// Headless host: starts an extension and drives its RPC lifecycle the way
/// Querya Desktop does, without a GUI.
///
/// Sequence: manifest check, launch, `system.handshake`, `system.ping`,
/// `db.connect`, `db.getCapabilities`, `db.getServerStats`,
/// `db.getSchemaTree`, `db.query`, `db.getTableSchema` (when a table is
/// given), `db.disconnect`, `system.shutdown`. Methods the emulated host
/// version does not send are skipped.
class QueryaExtensionHarness {
  QueryaExtensionHarness({
    HarnessLauncher? launcher,
    this.requestTimeout = const Duration(seconds: 5),
    this.shutdownTimeout = const Duration(seconds: 2),
  }) : _launcher = launcher ?? launchPluginProcess;

  final HarnessLauncher _launcher;
  final Duration requestTimeout;
  final Duration shutdownTimeout;

  static const _connectionId = 1;

  Future<HarnessReport> run({
    required String extensionRoot,
    required String targetVersion,
    HarnessConnectionOptions connection = const HarnessConnectionOptions(),
    bool sandbox = false,
  }) async {
    final total = Stopwatch()..start();
    final profile = ExtensionProtocolProfile.forTarget(targetVersion);
    final checks = <HarnessCheck>[];
    var extensionId = p.basename(extensionRoot);
    var abort = false;

    Future<void> step(
      String name,
      Future<void> Function() body, {
      HarnessMethodLevel level = HarnessMethodLevel.required,
    }) async {
      if (abort) {
        checks.add(HarnessCheck(
          name: name,
          status: HarnessCheckStatus.skipped,
          message: 'an earlier required step failed',
        ));
        return;
      }
      final sw = Stopwatch()..start();
      try {
        await body();
        checks.add(HarnessCheck(
          name: name,
          status: HarnessCheckStatus.passed,
          duration: sw.elapsed,
        ));
      } on _Warn catch (w) {
        checks.add(HarnessCheck(
          name: name,
          status: HarnessCheckStatus.warning,
          duration: sw.elapsed,
          message: w.message,
        ));
      } catch (e) {
        final failed = level == HarnessMethodLevel.required;
        checks.add(HarnessCheck(
          name: name,
          status: failed ? HarnessCheckStatus.failed : HarnessCheckStatus.warning,
          duration: sw.elapsed,
          message: _describe(e),
        ));
        if (failed) abort = true;
      }
    }

    // 1. Manifest.
    Map<String, Object?>? manifest;
    final manifestSw = Stopwatch()..start();
    final manifestFile = File(p.join(extensionRoot, 'manifest.json'));
    if (!manifestFile.existsSync()) {
      checks.add(HarnessCheck(
        name: 'manifest',
        status: HarnessCheckStatus.failed,
        duration: manifestSw.elapsed,
        message: 'manifest.json not found in $extensionRoot',
      ));
      abort = true;
    } else {
      try {
        final decoded = jsonDecode(await manifestFile.readAsString());
        final diagnostics = validateExtensionManifest(decoded, profile);
        if (decoded is Map) {
          manifest = Map<String, Object?>.from(decoded);
          extensionId = '${manifest['id'] ?? extensionId}';
        }
        final errors = diagnostics.where((d) => d.isError).toList();
        final text = diagnostics
            .map((d) => '${d.isError ? 'error' : 'warning'} $d')
            .join('\n');
        checks.add(HarnessCheck(
          name: 'manifest',
          status: errors.isNotEmpty
              ? HarnessCheckStatus.failed
              : diagnostics.isNotEmpty
                  ? HarnessCheckStatus.warning
                  : HarnessCheckStatus.passed,
          duration: manifestSw.elapsed,
          message: text.isEmpty ? null : text,
        ));
        if (errors.isNotEmpty) abort = true;
      } on FormatException catch (e) {
        checks.add(HarnessCheck(
          name: 'manifest',
          status: HarnessCheckStatus.failed,
          duration: manifestSw.elapsed,
          message: 'manifest.json is not valid JSON: ${e.message}',
        ));
        abort = true;
      }
    }

    // 2. Launch.
    HarnessPluginProcess? process;
    JsonRpcStdioClient? client;
    final stderrTail = <String>[];
    var peakRss = 0;
    Timer? rssTimer;
    int? exitCode;

    await step('launch', () async {
      final main = manifest?['main'];
      final entry = p.join(extensionRoot, main is String ? main : '');
      if (!File(entry).existsSync()) {
        throw StateError('entry point not found: $entry');
      }
      process = await _launcher(HarnessLaunchRequest(
        pluginId: extensionId,
        executable: entry,
        extensionRoot: extensionRoot,
        sandbox: sandbox,
      ));
      final proc = process!;
      unawaited(proc.exitCode.then((c) => exitCode = c, onError: (_) => -1));
      proc.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
        stderrTail.add(line);
        if (stderrTail.length > 20) stderrTail.removeAt(0);
      }, onError: (_) {});
      client = JsonRpcStdioClient(
        stdout: proc.stdout,
        stdin: proc.stdin,
        requestTimeout: requestTimeout,
      );
      rssTimer = Timer.periodic(const Duration(milliseconds: 100), (_) async {
        final rss = await _rssKb(proc.pid);
        if (rss != null && rss > peakRss) peakRss = rss;
      });
      final note = proc.sandboxNote;
      if (note != null) throw _Warn(note);
    });

    Future<Object?> call(String method, [Map<String, Object?>? params]) async {
      final c = client;
      if (c == null) throw StateError('plugin is not running');
      try {
        return await c.sendRequest(method, params);
      } on JsonRpcException catch (e) {
        if (e.code == -32601) {
          throw StateError('method "$method" is not implemented (-32601)');
        }
        throw StateError('"$method" returned an error: ${e.message}'
            '${e.code == null ? '' : ' (code ${e.code})'}');
      } on TimeoutException {
        throw StateError('"$method" did not answer within $requestTimeout'
            '${_crashHint(exitCode, stderrTail)}');
      } on StateError catch (e) {
        throw StateError('${e.message}${_crashHint(exitCode, stderrTail)}');
      }
    }

    Future<void> method(
      String name,
      Future<void> Function() body,
    ) async {
      final level = profile.levelOf(name);
      if (level == null) {
        checks.add(HarnessCheck(
          name: name,
          status: HarnessCheckStatus.skipped,
          message: 'not sent by Querya Desktop ${profile.targetVersion}',
        ));
        return;
      }
      await step(name, body, level: level);
    }

    final connectParams = <String, Object?>{
      'connectionId': _connectionId,
      if (connection.database != null) 'database': connection.database,
      ...connection.params,
    };
    final idOnly = <String, Object?>{'connectionId': _connectionId};

    await method('system.handshake', () async {
      await call('system.handshake', const {});
    });
    await method('system.ping', () async {
      await call('system.ping');
    });
    await method('db.connect', () async {
      await call('db.connect', connectParams);
    });
    await method('db.getCapabilities', () async {
      final r = await call('db.getCapabilities', idOnly);
      if (r != null && r is! Map) {
        throw StateError('result must be an object, got ${r.runtimeType}');
      }
    });
    await method('db.getServerStats', () async {
      final r = await call('db.getServerStats', idOnly);
      if (r != null && r is! Map) {
        throw StateError('result must be an object, got ${r.runtimeType}');
      }
    });
    await method('db.getSchemaTree', () async {
      final r = await call('db.getSchemaTree', idOnly);
      if (r is! Map && r is! List) {
        throw StateError(
            'result must be an object or a list of nodes, got ${r.runtimeType}');
      }
    });
    await method('db.query', () async {
      final r = await call('db.query', {
        ...idOnly,
        'sql': connection.query,
        'limit': 100,
      });
      if (r is! Map || r['columns'] is! List || r['rows'] is! List) {
        throw StateError(
          'result must be {"columns": [...], "rows": [...]}; the host shows an '
          'empty grid for anything else',
        );
      }
    });
    final table = connection.tableName;
    if (table != null && table.isNotEmpty) {
      await method('db.getTableSchema', () async {
        final r = await call('db.getTableSchema', {
          ...idOnly,
          'database': connection.database ?? '',
          'tableName': table,
        });
        if (r is! Map) {
          throw StateError('result must be an object, got ${r.runtimeType}');
        }
      });
    }
    await method('db.disconnect', () async {
      await call('db.disconnect', idOnly);
    });

    // system.shutdown runs even after earlier failures so the process is
    // always asked to exit cleanly first.
    if (process != null) {
      abort = false;
      await method('system.shutdown', () async {
        await call('system.shutdown');
        await process!.exitCode.timeout(shutdownTimeout, onTimeout: () {
          throw StateError('plugin did not exit within $shutdownTimeout '
              'after system.shutdown');
        });
      });
    }

    rssTimer?.cancel();
    await client?.close();
    await process?.dispose();
    total.stop();

    return HarnessReport(
      extensionId: extensionId,
      targetVersion: profile.targetVersion,
      checks: checks,
      totalDuration: total.elapsed,
      peakRssKb: peakRss > 0 ? peakRss : null,
    );
  }
}

/// Marks a step as passed-with-warning instead of failed.
final class _Warn implements Exception {
  const _Warn(this.message);
  final String message;
}

String _describe(Object e) =>
    e is StateError ? e.message : e.toString().replaceFirst('Exception: ', '');

String _crashHint(int? exitCode, List<String> stderrTail) {
  final b = StringBuffer();
  if (exitCode != null) b.write('; plugin exited with code $exitCode');
  if (stderrTail.isNotEmpty) {
    b.write('\nplugin stderr:\n${stderrTail.join('\n')}');
  }
  return b.toString();
}

/// Resident set size of [pid] in KiB, or null when the platform has no cheap
/// way to read it.
Future<int?> _rssKb(int pid) async {
  try {
    if (Platform.isLinux) {
      final status = await File('/proc/$pid/status').readAsString();
      final m = RegExp(r'VmRSS:\s+(\d+)\s+kB').firstMatch(status);
      return m == null ? null : int.parse(m.group(1)!);
    }
    if (Platform.isMacOS) {
      final r = await Process.run('ps', ['-o', 'rss=', '-p', '$pid']);
      return r.exitCode == 0 ? int.tryParse('${r.stdout}'.trim()) : null;
    }
  } catch (_) {}
  return null;
}
