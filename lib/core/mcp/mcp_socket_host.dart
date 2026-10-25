import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:querya_mcp_bridge/querya_mcp_bridge.dart';
import 'package:stream_channel/stream_channel.dart';

/// Accepts `querya-mcp` connections on `127.0.0.1` and hands each
/// authenticated one to [onSession] as a line-based [StreamChannel].
///
/// The first line of every connection must be the token from the endpoint
/// file; anything else closes the socket with a JSON-RPC error line.
class McpSocketHost {
  McpSocketHost({
    required this.endpointFile,
    required this.version,
    required this.onSession,
    this.handshakeTimeout = const Duration(seconds: 5),
    this.maxUnauthenticated = 16,
    this.maxHandshakeBytes = 4096,
    this.maxLineBytes = 4 * 1024 * 1024,
    this.maxSessions = 16,
  });

  final File endpointFile;
  final String version;
  final Future<void> Function(StreamChannel<String> channel) onSession;
  final Duration handshakeTimeout;

  /// Sockets that may wait for their token at once; more are turned away.
  final int maxUnauthenticated;

  /// Bytes accepted before the token line is complete (a token is ~44).
  final int maxHandshakeBytes;

  /// Bytes of one line from an authenticated client; a longer line (or one
  /// that never ends) closes the connection instead of growing in memory.
  final int maxLineBytes;

  /// Authenticated connections that may be open at once.
  final int maxSessions;

  ServerSocket? _server;
  String? _token;
  final _sockets = <Socket>{};
  var _unauthenticated = 0;

  bool get isRunning => _server != null;
  int? get port => _server?.port;

  /// Number of authenticated connections that are still open.
  int get sessionCount => _sessions;
  int _sessions = 0;

  final _changes = StreamController<void>.broadcast();

  /// Fires when the session count or the running state changes.
  Stream<void> get changes => _changes.stream;

  Future<void> start() async {
    if (_server != null) return;
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    _server = server;
    _token = McpEndpoint.newToken();
    server.listen(_accept);
    await McpEndpoint(
      port: server.port,
      token: _token!,
      pid: pid,
      version: version,
    ).write(endpointFile);
    _changes.add(null);
  }

  Future<void> stop() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    _token = null;
    await server.close();
    for (final s in _sockets.toList()) {
      s.destroy();
    }
    _sockets.clear();
    _sessions = 0;
    try {
      final current = await McpEndpoint.read(endpointFile);
      if (current == null || current.port == server.port) {
        await endpointFile.delete();
      }
    } on FileSystemException {
      // Already gone.
    }
    _changes.add(null);
  }

  void _accept(Socket socket) {
    if (_unauthenticated >= maxUnauthenticated) {
      socket.destroy();
      return;
    }
    _sockets.add(socket);
    _unauthenticated++;
    // A client that disappears mid-write must not surface as an uncaught error.
    unawaited(socket.done.then((_) {}, onError: (Object _) {}));
    final incoming = StreamController<String>();
    final outgoing = StreamController<String>();
    var authed = false;
    var waiting = true;
    var handshakeBytes = 0;
    var lineBytes = 0;
    void stopWaiting() {
      if (!waiting) return;
      waiting = false;
      _unauthenticated--;
    }

    final timer = Timer(handshakeTimeout, () {
      if (!authed) {
        stopWaiting();
        _reject(socket, 'Handshake timed out.');
      }
    });

    late final StreamSubscription<String> sub;
    sub = socket
        .cast<List<int>>()
        .map((chunk) {
          // Without a newline the line splitter would buffer without bound.
          if (!authed && (handshakeBytes += chunk.length) > maxHandshakeBytes) {
            timer.cancel();
            sub.cancel();
            stopWaiting();
            _reject(socket, 'Handshake too long.');
            return const <int>[];
          }
          if (authed) {
            final newline = chunk.lastIndexOf(0x0A);
            lineBytes =
                newline >= 0 ? chunk.length - newline - 1 : lineBytes + chunk.length;
            if (lineBytes > maxLineBytes) {
              sub.cancel();
              _closed(socket, incoming, outgoing, authed);
              return const <int>[];
            }
          }
          return chunk;
        })
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
      (line) {
        if (authed) {
          incoming.add(line);
          return;
        }
        final token = _token;
        if (token == null || !McpEndpoint.tokensEqual(line.trim(), token)) {
          timer.cancel();
          sub.cancel();
          stopWaiting();
          _reject(socket, 'Invalid Querya MCP token. Restart the MCP client.');
          return;
        }
        if (_sessions >= maxSessions) {
          timer.cancel();
          sub.cancel();
          stopWaiting();
          _reject(socket, 'Too many Querya MCP sessions.');
          return;
        }
        authed = true;
        lineBytes = 0;
        stopWaiting();
        timer.cancel();
        _sessions++;
        _changes.add(null);
        outgoing.stream.listen(
          (l) => socket.write('$l\n'),
          onDone: () => socket.destroy(),
        );
        unawaited(onSession(StreamChannel.withCloseGuarantee(
            incoming.stream, outgoing.sink)));
      },
      onDone: () {
        stopWaiting();
        _closed(socket, incoming, outgoing, authed);
      },
      onError: (_) {
        stopWaiting();
        _closed(socket, incoming, outgoing, authed);
      },
      cancelOnError: true,
    );
  }

  void _closed(
    Socket socket,
    StreamController<String> incoming,
    StreamController<String> outgoing,
    bool authed,
  ) {
    if (_sockets.remove(socket) && authed) {
      _sessions--;
      _changes.add(null);
    }
    unawaited(incoming.close());
    // The channel guarantees no write after the incoming side closed.
    unawaited(outgoing.close());
    socket.destroy();
  }

  void _reject(Socket socket, String message) {
    socket.write('${jsonEncode({
          'jsonrpc': '2.0',
          'id': null,
          'error': {'code': -32001, 'message': message},
        })}\n');
    unawaited(socket.flush().whenComplete(socket.destroy));
    _sockets.remove(socket);
  }
}
