import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';

/// In-memory stand-in for an SSH server and its clients, plugged into
/// `SshTunnelManager.forTesting`. No sockets leave the process; only the
/// tunnel's own loopback listener is real.
class FakeSshServer {
  FakeSshServer({
    this.password = 'secret',
    List<int>? hostKey,
    this.acceptPublicKeys = true,
    this.failConnect = false,
  }) : hostKey = Uint8List.fromList(hostKey ?? const [1, 2, 3, 4]);

  /// Password the server accepts.
  String password;

  /// Per-user passwords that take precedence over [password].
  final userPasswords = <String, String>{};

  /// The server's host key. What the client's verify callback receives is its
  /// OpenSSH fingerprint, `SHA256:<base64>` UTF-8 encoded, as dartssh2 passes it.
  Uint8List hostKey;

  /// The fingerprint of [key], as OpenSSH prints it.
  static String openSshFingerprint(List<int> key) =>
      'SHA256:${base64.encode(sha256.convert(key).bytes).replaceAll('=', '')}';

  /// What dartssh2 hands to `onVerifyHostKey` for [key].
  static Uint8List presented(List<int> key) =>
      Uint8List.fromList(utf8.encode(openSshFingerprint(key)));

  /// Whether public-key authentication succeeds.
  bool acceptPublicKeys;

  /// Makes the TCP connect fail.
  bool failConnect;

  /// When set, the handshake of every client fails with this (a reset, a
  /// protocol error) before any credential is judged.
  Object? failHandshake;

  /// How long the TCP connect takes, to land another call inside it.
  Duration? connectDelay;

  /// Every (host, port) the manager dialed, in order.
  final connects = <({String host, int port})>[];

  /// Every client the manager built, in order.
  final clients = <FakeSshClient>[];

  Future<SSHSocket> connect(
    String host,
    int port, {
    Duration? timeout,
  }) async {
    connects.add((host: host, port: port));
    final delay = connectDelay;
    if (delay != null) await Future<void>.delayed(delay);
    if (failConnect) throw StateError('connect to $host:$port failed');
    return FakeSshSocket();
  }

  SSHClient build(
    SSHSocket socket, {
    required String username,
    SSHPasswordRequestHandler? onPasswordRequest,
    List<SSHKeyPair>? identities,
    SSHHostkeyVerifyHandler? onVerifyHostKey,
  }) {
    final client = FakeSshClient(
      server: this,
      socket: socket,
      username: username,
      onPasswordRequest: onPasswordRequest,
      identities: identities,
      onVerifyHostKey: onVerifyHostKey,
    );
    clients.add(client);
    return client;
  }
}

/// A transport that carries nothing; the fake client never reads it.
class FakeSshSocket implements SSHSocket {
  // The fake owns this stream for the whole test.
  // ignore: close_sinks
  final _in = StreamController<Uint8List>();
  // The fake owns this stream for the whole test.
  // ignore: close_sinks
  final _out = StreamController<List<int>>();

  @override
  Stream<Uint8List> get stream => _in.stream;

  @override
  StreamSink<List<int>> get sink => _out.sink;

  @override
  Future<void> get done => Future<void>.value();

  @override
  Future<void> close() async {}

  @override
  void destroy() {}

  @override
  Future<void> flush() async {}
}

/// Scripted SSH client: runs a host-key check, then password or public-key
/// authentication against [server], and echoes forwarded connections.
class FakeSshClient implements SSHClient {
  FakeSshClient({
    required this.server,
    required this.socket,
    required this.username,
    this.onPasswordRequest,
    this.identities,
    this.onVerifyHostKey,
  }) {
    unawaited(_handshake());
  }

  final FakeSshServer server;

  @override
  final SSHSocket socket;

  @override
  final String username;

  @override
  final SSHPasswordRequestHandler? onPasswordRequest;

  @override
  final List<SSHKeyPair>? identities;

  @override
  final SSHHostkeyVerifyHandler? onVerifyHostKey;

  final _authenticated = Completer<void>();
  var _closed = false;

  /// Host/port pairs requested through `forwardLocal`.
  final forwards = <({String host, int port})>[];
  var pingCount = 0;

  /// Password the manager supplied when asked, if it was asked.
  String? suppliedPassword;

  /// Whether the manager asked this client for a password.
  var passwordRequested = false;

  /// Bytes written by tunnel users, per forwarded connection, uppercased back.
  final received = <List<int>>[];

  Future<void> _handshake() async {
    try {
      final broken = server.failHandshake;
      if (broken != null) throw broken;
      final trusted =
          await onVerifyHostKey?.call(
                'ssh-ed25519',
                FakeSshServer.presented(server.hostKey),
              ) ??
              true;
      if (!trusted) throw SSHHostkeyError('host key rejected');

      final keys = identities;
      if (keys != null && keys.isNotEmpty) {
        if (!server.acceptPublicKeys) {
          throw SSHAuthFailError('public key rejected');
        }
      } else {
        passwordRequested = onPasswordRequest != null;
        suppliedPassword = await onPasswordRequest?.call();
        if (suppliedPassword != (server.userPasswords[username] ?? server.password)) {
          throw SSHAuthFailError('password rejected');
        }
      }
      _authenticated.complete();
    } catch (e, st) {
      _authenticated.completeError(e, st);
    }
  }

  @override
  Future<void> get authenticated => _authenticated.future;

  /// If true, calls to [ping] will throw.
  var failPing = false;

  @override
  bool get isClosed => _closed;

  @override
  Future<void> close() async {
    _closed = true;
  }

  @override
  Future<void> ping() async {
    pingCount++;
    if (failPing) throw StateError('ping failed');
  }

  @override
  Future<SSHForwardChannel> forwardLocal(
    String remoteHost,
    int remotePort, {
    String localHost = 'localhost',
    int localPort = 0,
  }) async {
    if (_closed) throw StateError('client closed');
    forwards.add((host: remoteHost, port: remotePort));
    return _EchoForwardChannel(received);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}

/// Forwarded channel that answers every chunk with its uppercase form.
class _EchoForwardChannel implements SSHForwardChannel {
  _EchoForwardChannel(this._received) {
    _sink.stream.listen((chunk) {
      _received.add(chunk);
      _reply.add(
        Uint8List.fromList(String.fromCharCodes(chunk).toUpperCase().codeUnits),
      );
    }, onDone: () => _reply.close());
  }

  final List<List<int>> _received;
  final _sink = StreamController<List<int>>();
  final _reply = StreamController<Uint8List>();

  @override
  Stream<Uint8List> get stream => _reply.stream;

  @override
  StreamSink<List<int>> get sink => _sink.sink;

  @override
  Future<void> close() async {
    await _sink.close();
  }

  @override
  Future<void> get done => _reply.done;

  @override
  void destroy() {
    _sink.close();
  }

  @override
  Future<void> flush() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not faked');
}
