import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:querya_mcp_bridge/querya_mcp_bridge.dart';
import 'package:querya_desktop/core/mcp/mcp_socket_host.dart';

void main() {
  late Directory tempDir;
  late McpSocketHost host;

  Future<void> startHost({
    int maxUnauthenticated = 16,
    int maxSessions = 16,
    int maxLineBytes = 4 * 1024 * 1024,
  }) async {
    host = McpSocketHost(
      endpointFile: File(p.join(tempDir.path, 'mcp.json')),
      version: 'test',
      onSession: (_) async {},
      maxUnauthenticated: maxUnauthenticated,
      maxHandshakeBytes: 64,
      maxSessions: maxSessions,
      maxLineBytes: maxLineBytes,
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

  Future<Socket> connectAuthed() async {
    final endpoint = await McpEndpoint.read(File(p.join(tempDir.path, 'mcp.json')));
    final socket =
        await Socket.connect(InternetAddress.loopbackIPv4, host.port!);
    socket.write('${endpoint!.token}\n');
    await socket.flush();
    return socket;
  }

  test('sessions beyond the cap are turned away (#1776)', () async {
    await startHost(maxSessions: 1);
    final first = await connectAuthed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(host.sessionCount, 1);

    final second = await connectAuthed();
    final reply = await utf8.decodeStream(second).timeout(const Duration(seconds: 3));

    expect(reply, contains('Too many'));
    expect(host.sessionCount, 1);
    first.destroy();
  });

  test('an authenticated line without a newline is cut off (#1776)', () async {
    await startHost(maxLineBytes: 100);
    final socket = await connectAuthed();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(host.sessionCount, 1);

    socket.add(List.filled(300, 0x41));
    await socket.flush();

    await socket.drain<void>().timeout(const Duration(seconds: 3));
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(host.sessionCount, 0);
  });
}
