// querya-ext-tester: headless test runner for Querya extensions (database
// drivers). Released as a standalone executable built with
// `dart compile exe bin/querya_ext_tester.dart`.
//
//   dart run bin/querya_ext_tester.dart <extension-dir> [options]
//
// Exit codes: 0 all checks passed, 1 a check failed, 2 bad usage.
import 'dart:convert';
import 'dart:io';

import 'package:querya_desktop/core/extensions/harness/extension_harness.dart';
import 'package:querya_desktop/core/extensions/harness/extension_protocol_profile.dart';

const _usage = '''
Usage: querya-ext-tester <extension-dir> [options]

Starts the extension like Querya Desktop does and checks its JSON-RPC
lifecycle without a GUI.

Options:
  --target-version <x.y.z>  Querya Desktop version to emulate (default 0.5.0)
  --connect <json|file>     db.connect parameters: inline JSON or a JSON file
  --query <sql>             statement for the db.query check (default SELECT 1)
  --table <name>            also check db.getTableSchema for this table
  --database <name>         database passed to db.connect
  --sandbox                 run the plugin in the OS sandbox when available
  --timeout-ms <n>          per-request timeout (default 5000)
  --junit <path>            write a JUnit XML report
  --tap <path>              write a TAP report
  --no-color                disable ANSI colors
  -h, --help                show this help
''';

Future<int> main(List<String> args) async {
  String? dir;
  var target = '0.5.0';
  String? connect;
  var query = 'SELECT 1';
  String? table;
  String? database;
  var sandbox = false;
  var timeoutMs = 5000;
  String? junit;
  String? tap;
  var color = stdout.hasTerminal;

  String? value(int i, String flag) {
    if (i + 1 >= args.length) {
      stderr.writeln('$flag needs a value');
      return null;
    }
    return args[i + 1];
  }

  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    switch (a) {
      case '-h' || '--help':
        stdout.write(_usage);
        return 0;
      case '--sandbox':
        sandbox = true;
      case '--no-color':
        color = false;
      case '--target-version' ||
            '--connect' ||
            '--query' ||
            '--table' ||
            '--database' ||
            '--timeout-ms' ||
            '--junit' ||
            '--tap':
        final v = value(i, a);
        if (v == null) return 2;
        i++;
        switch (a) {
          case '--target-version':
            target = v;
          case '--connect':
            connect = v;
          case '--query':
            query = v;
          case '--table':
            table = v;
          case '--database':
            database = v;
          case '--timeout-ms':
            final n = int.tryParse(v);
            if (n == null || n <= 0) {
              stderr.writeln('--timeout-ms must be a positive integer');
              return 2;
            }
            timeoutMs = n;
          case '--junit':
            junit = v;
          case '--tap':
            tap = v;
        }
      default:
        if (a.startsWith('-') || dir != null) {
          stderr
            ..writeln('Unexpected argument: $a')
            ..write(_usage);
          return 2;
        }
        dir = a;
    }
  }

  if (dir == null) {
    stderr.write(_usage);
    return 2;
  }

  Map<String, Object?> connectParams = const {};
  if (connect != null) {
    try {
      final raw = File(connect).existsSync()
          ? File(connect).readAsStringSync()
          : connect;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) throw const FormatException('expected an object');
      connectParams = Map<String, Object?>.from(decoded);
    } on FormatException catch (e) {
      stderr.writeln('--connect is not a JSON object or file: ${e.message}');
      return 2;
    }
  }

  try {
    ExtensionProtocolProfile.forTarget(target);
  } on FormatException catch (e) {
    stderr.writeln('--target-version: ${e.message}: ${e.source}');
    return 2;
  } on ArgumentError catch (e) {
    stderr.writeln('--target-version: ${e.message}');
    return 2;
  }
  final harness = QueryaExtensionHarness(
    requestTimeout: Duration(milliseconds: timeoutMs),
  );
  final report = await harness.run(
    extensionRoot: Directory(dir).absolute.path,
    targetVersion: target,
    connection: HarnessConnectionOptions(
      params: connectParams,
      query: query,
      tableName: table,
      database: database,
    ),
    sandbox: sandbox,
  );
  stdout.write(report.toConsole(color: color));
  if (junit != null) File(junit).writeAsStringSync(report.toJUnitXml());
  if (tap != null) File(tap).writeAsStringSync(report.toTap());
  return report.isSuccess ? 0 : 1;
}
