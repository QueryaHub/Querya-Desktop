import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/mcp/mcp_socket_host.dart';

void main() {
  late Directory tempDir;
  late McpSocketHost host;

  Future<void> startHost({int maxUnauthenticated = 16}) async {
    host = McpSocketHost(
      endpointFile: File(p.join(tempDir.path, 'mcp.json')),
      version: 'test',
      onSession: (_) async {},
      maxUnauthenticated: maxUnauthenticated,
      maxHandshakeBytes: 64,
    );
    await host.start();
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('querya_mcp_host_');
  });

  tearDown(() async {
    if (host.isRunning) await host.stop();
    await tempDir.delete(recursive: true);
  });

  test('a handshake line without a newline is cut off at the limit (#1565)',
      () async {
    await startHost();
    final socket = await Socket.connect(InternetAddress.loopbackIPv4, host.port!);
    final reply = utf8.decodeStream(socket);
    socket.add(List.filled(200, 0x41));
    await socket.flush();

    expect(await reply.timeout(const Duration(seconds: 3)),
        contains('Handshake too long'));
    socket.destroy();
  });

  test('sockets beyond the unauthenticated cap are turned away (#1565)',
      () async {
    await startHost(maxUnauthenticated: 1);
    final first = await Socket.connect(InternetAddress.loopbackIPv4, host.port!);
    // Let the host register the first one before the second arrives.
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final second = await Socket.connect(InternetAddress.loopbackIPv4, host.port!);

    await second.drain<void>().timeout(const Duration(seconds: 3));
    first.destroy();
    second.destroy();
  });
}
