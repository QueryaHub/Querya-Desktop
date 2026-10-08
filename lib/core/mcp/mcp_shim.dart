import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:querya_desktop/core/mcp/mcp_endpoint.dart';

/// Message for clients when the app is not reachable.
const kMcpAppNotRunning =
    'Querya Desktop is not running or its MCP server is off. Start Querya '
    'Desktop and enable the MCP server in Settings, then retry.';

/// `querya-mcp`: forwards an MCP stdio session to the running app.
///
/// Sends the token from the endpoint file as the first line, then pipes bytes
/// both ways without parsing MCP. When the app cannot be reached it answers
/// every request on [input] with a JSON-RPC error carrying
/// [kMcpAppNotRunning] until [input] closes, so the client shows a clear
/// message. Returns the process exit code.
Future<int> runMcpShim({
  required Stream<List<int>> input,
  required IOSink output,
  required IOSink errors,
  File? endpointFile,
  Duration connectTimeout = const Duration(seconds: 3),
}) async {
  final file = endpointFile ?? McpEndpoint.defaultFile();
  final endpoint = await McpEndpoint.read(file);
  Socket? socket;
  if (endpoint != null) {
    try {
      socket = await Socket.connect(
        InternetAddress.loopbackIPv4,
        endpoint.port,
        timeout: connectTimeout,
      );
    } on SocketException {
      socket = null;
    }
  }

  if (endpoint == null || socket == null) {
    errors.writeln('querya-mcp: $kMcpAppNotRunning (endpoint: ${file.path})');
    await _answerUnavailable(input, output);
    return 1;
  }

  socket.setOption(SocketOption.tcpNoDelay, true);
  socket.write('${endpoint.token}\n');

  final done = Completer<int>();
  final toApp = input.listen(
    socket.add,
    onDone: () async {
      await socket!.flush();
      await socket.close();
    },
    cancelOnError: true,
  );
  socket.listen(
    output.add,
    onDone: () {
      if (!done.isCompleted) done.complete(0);
    },
    onError: (Object e) {
      errors.writeln('querya-mcp: connection to Querya Desktop lost: $e');
      if (!done.isCompleted) done.complete(1);
    },
  );
  final code = await done.future;
  await toApp.cancel();
  await output.flush();
  socket.destroy();
  return code;
}

Future<void> _answerUnavailable(
  Stream<List<int>> input,
  IOSink output,
) async {
  await for (final line
      in input.transform(utf8.decoder).transform(const LineSplitter())) {
    Object? id;
    try {
      final msg = jsonDecode(line);
      if (msg is Map) id = msg['id'];
    } catch (_) {
      continue;
    }
    if (id == null) continue; // notifications get no answer
    output.writeln(jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'error': {'code': -32000, 'message': kMcpAppNotRunning},
    }));
    await output.flush();
  }
}
