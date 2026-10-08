import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Why scenarios that start a real driver process cannot run here, or null.
String? stubDriverSkipReason() {
  if (Platform.isWindows) return 'the stub driver is a POSIX script';
  try {
    if (Process.runSync('python3', const ['--version']).exitCode == 0) {
      return null;
    }
  } catch (_) {}
  return 'python3 is not available';
}

Map<String, Object?> stubManifest() => {
      'id': 'acme.stub',
      'name': 'Stub',
      'version': '1.0.0',
      'type': 'database_driver',
      'main': 'bin/driver',
      'engines': {'querya_desktop': '^0.4.11'},
      'contributions': {
        'drivers': [
          {'driverId': 'stub', 'displayName': 'Stub'},
        ],
      },
    };

/// Writes a manifest and an executable JSON-RPC driver speaking newline
/// delimited JSON over stdio.
///
/// [mode]: `healthy` answers everything, `mute` ignores `system.handshake`,
/// `probe` tries to create [probeFile] during `db.query`.
void writeStubDriver(Directory root, {required String mode, String? probeFile}) {
  File(p.join(root.path, 'manifest.json'))
      .writeAsStringSync(jsonEncode(stubManifest()));
  final entry = File(p.join(root.path, 'bin', 'driver'))
    ..createSync(recursive: true)
    ..writeAsStringSync('''#!/usr/bin/env python3
import json
import sys

MODE = ${jsonEncode(mode)}
PROBE = ${jsonEncode(probeFile ?? '')}


def reply(i, result=None):
    sys.stdout.write(json.dumps({"jsonrpc": "2.0", "id": i, "result": result}) + "\\n")
    sys.stdout.flush()


for line in sys.stdin:
    msg = json.loads(line)
    method = msg["method"]
    i = msg.get("id")
    if MODE == "mute" and method == "system.handshake":
        continue
    if method == "system.shutdown":
        reply(i)
        sys.exit(0)
    if method == "system.handshake":
        result = {"protocolVersion": 1}
    elif method == "system.ping":
        result = "pong"
    elif method == "db.connect":
        result = {"serverVersion": "e2e"}
    elif method == "db.getCapabilities":
        result = {"supportsTransactions": False}
    elif method == "db.getServerStats":
        result = {"uptime": 1}
    elif method == "db.getSchemaTree":
        result = {"nodes": []}
    elif method == "db.query":
        if MODE == "probe" and PROBE:
            try:
                with open(PROBE, "w") as f:
                    f.write("escaped")
            except OSError:
                pass
        result = {"columns": ["one"], "rows": [[1]]}
    elif method == "db.getTableSchema":
        result = {"columns": []}
    else:
        result = None
    reply(i, result)
''');
  Process.runSync('chmod', ['+x', entry.path]);
}
