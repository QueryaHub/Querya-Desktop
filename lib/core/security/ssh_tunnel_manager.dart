import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';

/// Result of an SSH connection diagnostic test.
class SshTestResult {
  const SshTestResult({
    required this.ok,
    this.message,
    this.error,
    this.serverFingerprint,
  });

  final bool ok;
  final String? message;
  final String? error;
  final String? serverFingerprint;
}

/// Handle to an active ephemeral local port forwarding tunnel.
class SshTunnelHandle {
  SshTunnelHandle({
    required this.localHost,
    required this.localPort,
    required this.remoteHost,
    required this.remotePort,
    required Future<void> Function() onRelease,
  }) : _onRelease = onRelease;

  /// Always '127.0.0.1' (strictly loopback).
  final String localHost;

  /// Dynamic local port bound on 127.0.0.1.
  final int localPort;

  /// Destination target database host behind the bastion.
  final String remoteHost;

  /// Destination target database port behind the bastion.
  final int remotePort;

  final Future<void> Function() _onRelease;
  bool _released = false;

  /// Decrements ref-count and tears down socket/SSH session when no callers remain.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _onRelease();
  }
}

/// Active pooled SSH tunnel session.
class _PooledTunnelSession {
  _PooledTunnelSession({
    required this.poolKey,
    required this.client,
    required this.serverSocket,
    required this.localPort,
    this.jumpClient,
    this.keepAliveTimer,
  });

  final String poolKey;
  final SSHClient client;
  final ServerSocket serverSocket;
  final int localPort;
  final SSHClient? jumpClient;
  Timer? keepAliveTimer;
  int refCount = 1;

  Future<void> close() async {
    keepAliveTimer?.cancel();
    keepAliveTimer = null;
    try {
      await serverSocket.close();
    } catch (_) {}
    try {
      unawaited(client.close());
    } catch (_) {}
    try {
      unawaited(jumpClient?.close());
    } catch (_) {}
  }
}

/// Opens the raw TCP transport to an SSH server (replaceable in tests).
typedef SshSocketConnector = Future<SSHSocket> Function(
  String host,
  int port, {
  Duration? timeout,
});

/// Builds the SSH client over an open transport (replaceable in tests).
typedef SshClientBuilder = SSHClient Function(
  SSHSocket socket, {
  required String username,
  SSHPasswordRequestHandler? onPasswordRequest,
  List<SSHKeyPair>? identities,
  SSHHostkeyVerifyHandler? onVerifyHostKey,
});

SSHClient _defaultClientBuilder(
  SSHSocket socket, {
  required String username,
  SSHPasswordRequestHandler? onPasswordRequest,
  List<SSHKeyPair>? identities,
  SSHHostkeyVerifyHandler? onVerifyHostKey,
}) =>
    SSHClient(
      socket,
      username: username,
      onPasswordRequest: onPasswordRequest,
      identities: identities,
      onVerifyHostKey: onVerifyHostKey,
    );

/// Singleton manager for production SSH tunnels (Bastion / Jump Hosts).
/// Supports ephemeral local port forwarding, TLS over SSH, ref-counting,
/// host key fingerprint verification, and zero-leak credential hygiene.
class SshTunnelManager {
  SshTunnelManager._()
      : _connect = SSHSocket.connect,
        _buildClient = _defaultClientBuilder;

  /// A manager whose network transport and SSH client are supplied by the
  /// caller, so the tunnel logic can be exercised without an SSH server.
  @visibleForTesting
  SshTunnelManager.forTesting({
    required SshSocketConnector connector,
    required SshClientBuilder clientBuilder,
  })  : _connect = connector,
        _buildClient = clientBuilder;

  static SshTunnelManager instance = SshTunnelManager._();

  final SshSocketConnector _connect;
  final SshClientBuilder _buildClient;

  final Map<String, _PooledTunnelSession> _sessions = {};

  /// Number of pooled tunnel sessions currently open.
  @visibleForTesting
  int get activeSessionCount => _sessions.length;

  /// The host key fingerprint as OpenSSH writes it: `SHA256:<base64>`, what
  /// `ssh-keygen -lf` and `ssh-keyscan | ssh-keygen -lf -` print.
  ///
  /// dartssh2 hands the verify callback that string, UTF-8 encoded, not the
  /// key; hashing those bytes again (as this method used to) gave a value no
  /// other tool shows, and a fingerprint copied from one never matched (#1304).
  static String formatFingerprint(Uint8List bytes) =>
      utf8.decode(bytes, allowMalformed: true).trim();

  /// Whether [pinned], what the user saved, is the host key [presented] by the
  /// server. Accepted spellings:
  /// - `SHA256:<base64>` as OpenSSH prints it (the prefix in any case, the
  ///   base64 with or without padding; the base64 itself is case-sensitive);
  /// - the bare base64 of it;
  /// - the 64-digit hex a Querya version before this fix displayed (a SHA-256
  ///   of the OpenSSH string, with or without `:`), so saved pins keep working.
  static bool fingerprintMatches(String pinned, Uint8List presented) {
    final observed = formatFingerprint(presented);
    final text = pinned.trim();
    if (text.isEmpty) return true;

    String bare(String v) => v.replaceAll('=', '');
    final observedBase64 = observed.startsWith('SHA256:')
        ? bare(observed.substring(7))
        : bare(observed);

    final prefix = RegExp(r'^sha256:', caseSensitive: false);
    if (prefix.hasMatch(text)) {
      return bare(text.substring(7)) == observedBase64;
    }
    final legacyHex = sha256.convert(presented).toString();
    final hex = text.replaceAll(':', '').toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return hex == legacyHex;
    return bare(text) == observedBase64;
  }

  /// Opens the transport to [host]:[port]; a failure names the host, so it is
  /// not mistaken for a database problem (#1305).
  Future<SSHSocket> _dial(
    String host,
    int port,
    Duration timeout, {
    required String what,
  }) async {
    try {
      return await _connect(host, port, timeout: timeout);
    } catch (e) {
      throw SshConnectionException('Cannot reach the $what $host:$port: $e');
    }
  }

  /// What a failed SSH login or handshake is reported as: a rejected
  /// credential is an authentication failure; anything else (a reset, a
  /// timeout, a protocol error) is a connection failure, not a wrong password.
  static Object _sshFailure(Object e, String user, String host, int port) {
    if (e is SshAuthenticationException ||
        e is SshHostKeyMismatchException ||
        e is SshConnectionException) {
      return e;
    }
    if (e is SSHAuthError) {
      return SshAuthenticationException(
        'SSH authentication failed for ${user.trim()}@${host.trim()}: $e',
      );
    }
    return SshConnectionException(
      'The SSH connection to ${host.trim()}:$port failed: $e',
    );
  }

  /// Establishes or reuses an ephemeral local port forwarding tunnel.
  Future<SshTunnelHandle> openTunnel({
    required SshTunnelConfig config,
    required SshTunnelSecrets secrets,
    required String remoteHost,
    required int remotePort,
  }) async {
    final poolKey = '${config.host}:${config.port}:${config.username}:'
        '${config.jumpHost ?? ""}:${config.jumpPort ?? ""}'
        '@$remoteHost:$remotePort';

    // 1. Check if an active session can be reused (ref-counting)
    final existing = _sessions[poolKey];
    if (existing != null && existing.client.isClosed) {
      // The SSH connection dropped (network error, server restart): drop the
      // stale session, including its local listener, and dial again below.
      _sessions.remove(poolKey);
      unawaited(existing.close());
    } else if (existing != null) {
      existing.refCount++;
      // The caller's credentials are not needed for a reused session.
      secrets.zero();
      return SshTunnelHandle(
        localHost: '127.0.0.1',
        localPort: existing.localPort,
        remoteHost: remoteHost,
        remotePort: remotePort,
        onRelease: () => _releaseSession(existing),
      );
    }

    // 2. Connect to SSH Bastion (with optional Jump Host)
    SSHClient? jumpClient;
    final SSHSocket bastionSocket;

    if (config.jumpHost != null && config.jumpHost!.trim().isNotEmpty) {
      final jumpHost = config.jumpHost!.trim();
      final jumpPort = config.jumpPort ?? 22;
      final jumpUser = config.jumpUsername ?? config.username;

      final rawJumpSocket = await _dial(
        jumpHost,
        jumpPort,
        Duration(seconds: config.connectTimeoutSeconds),
        what: 'SSH jump host',
      );

      jumpClient = _buildClient(
        rawJumpSocket,
        username: jumpUser,
        onPasswordRequest: () =>
            secrets.jumpPassword ?? secrets.password ?? '',
      );
      try {
        await jumpClient.authenticated;
      } catch (e) {
        unawaited(jumpClient.close());
        throw _sshFailure(e, jumpUser, jumpHost, jumpPort);
      }

      // Forward through jump host to target bastion (returns SSHForwardChannel which implements SSHSocket)
      try {
        bastionSocket =
            await jumpClient.forwardLocal(config.host.trim(), config.port);
      } catch (e) {
        unawaited(jumpClient.close());
        throw SshConnectionException(
          'The SSH jump host $jumpHost:$jumpPort could not reach the bastion '
          '${config.host.trim()}:${config.port}: $e',
        );
      }
    } else {
      bastionSocket = await _dial(
        config.host.trim(),
        config.port,
        Duration(seconds: config.connectTimeoutSeconds),
        what: 'SSH server',
      );
    }

    // Prepare identities for private key auth
    List<SSHKeyPair> identities = [];
    if (config.authType == SshAuthType.privateKey) {
      String? keyContent = secrets.privateKey;
      if ((keyContent == null || keyContent.isEmpty) &&
          config.privateKeyPath != null &&
          config.privateKeyPath!.trim().isNotEmpty) {
        final file = File(config.privateKeyPath!.trim());
        if (await file.exists()) {
          keyContent = await file.readAsString();
        }
      }

      if (keyContent != null && keyContent.isNotEmpty) {
        try {
          identities = SSHKeyPair.fromPem(
            keyContent,
            secrets.passphrase,
          );
        } catch (e) {
          throw SshAuthenticationException(
            'Failed to parse private key: $e',
          );
        }
      }
    }

    // Host key verification (MitM protection)
    String? observedFingerprint;
    Future<bool> handleVerifyHostKey(String type, Uint8List fingerprint) async {
      observedFingerprint = formatFingerprint(fingerprint);
      final pinned = config.knownHostFingerprint;
      if (pinned == null || pinned.trim().isEmpty) {
        return true; // TOFU / accept-new
      }
      if (!fingerprintMatches(pinned, fingerprint)) {
        debugPrint(
          'SSH Host Key Mismatch! Expected: ${pinned.trim()}, '
          'Actual: $observedFingerprint',
        );
        return false;
      }
      return true;
    }

    final client = _buildClient(
      bastionSocket,
      username: config.username.trim(),
      onPasswordRequest: () => secrets.password ?? '',
      identities: identities.isNotEmpty ? identities : null,
      onVerifyHostKey: handleVerifyHostKey,
    );

    try {
      await client.authenticated;
    } catch (e) {
      unawaited(client.close());
      unawaited(jumpClient?.close());
      if (observedFingerprint != null &&
          config.knownHostFingerprint != null &&
          config.knownHostFingerprint!.isNotEmpty) {
        throw SshHostKeyMismatchException(
          'SSH host key verification failed for ${config.host}. '
          'Observed fingerprint: $observedFingerprint',
        );
      }
      throw _sshFailure(e, config.username, config.host, config.port);
    }

    // Zero sensitive in-memory credentials immediately after successful authentication
    secrets.zero();

    // 3. Start local ephemeral port forwarding on 127.0.0.1:0
    final serverSocket = await ServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    final localPort = serverSocket.port;

    serverSocket.listen(
      (clientSocket) async {
        try {
          final forward = await client.forwardLocal(remoteHost, remotePort);
          unawaited(forward.stream.cast<List<int>>().pipe(clientSocket).catchError((_) {}));
          unawaited(clientSocket.cast<List<int>>().pipe(forward.sink).catchError((_) {}));
        } catch (e) {
          clientSocket.destroy();
        }
      },
      onError: (_) {},
    );

    // 4. Setup keep-alive ping timer
    Timer? keepAliveTimer;
    _PooledTunnelSession? session;
    if (config.keepAliveIntervalSeconds > 0) {
      var failedPings = 0;
      keepAliveTimer = Timer.periodic(
        Duration(seconds: config.keepAliveIntervalSeconds),
        (_) async {
          if (client.isClosed) {
            if (session != null) {
              await _dropZombieSession(session);
            }
            return;
          }
          try {
            await client.ping();
            failedPings = 0;
          } catch (_) {
            failedPings++;
            if (failedPings >= _maxKeepAlivePingFailures) {
              if (session != null) {
                await _dropZombieSession(session);
              }
            }
          }
        },
      );
    }

    session = _PooledTunnelSession(
      poolKey: poolKey,
      client: client,
      serverSocket: serverSocket,
      localPort: localPort,
      jumpClient: jumpClient,
      keepAliveTimer: keepAliveTimer,
    );
    _sessions[poolKey] = session;

    return SshTunnelHandle(
      localHost: '127.0.0.1',
      localPort: localPort,
      remoteHost: remoteHost,
      remotePort: remotePort,
      onRelease: () => _releaseSession(session!),
    );
  }

  /// Number of consecutive failed keep-alive pings before considering the
  /// SSH session dead and proactively closing the local forwarder and client.
  static const int _maxKeepAlivePingFailures = 2;

  /// Proactively drops a zombie session whose SSH connection or keep-alive pings
  /// failed, closing the local listener and SSH client and evicting it from the pool.
  Future<void> _dropZombieSession(_PooledTunnelSession session) async {
    if (identical(_sessions[session.poolKey], session)) {
      _sessions.remove(session.poolKey);
    }
    await session.close();
  }

  /// Drops one reference to [session]; the last one closes it. Handles keep a
  /// reference to their own session, so a handle from a replaced (dropped)
  /// session cannot release the session that took its place.
  Future<void> _releaseSession(_PooledTunnelSession session) async {
    session.refCount--;
    if (session.refCount > 0) return;
    if (identical(_sessions[session.poolKey], session)) {
      _sessions.remove(session.poolKey);
    }
    await session.close();
  }

  /// Closes all active tunnels and cleans up all sockets.
  Future<void> closeAll() async {
    final active = List<_PooledTunnelSession>.from(_sessions.values);
    _sessions.clear();
    for (final s in active) {
      await s.close();
    }
  }

  /// Tests the Bastion connection and remote target reachability.
  Future<SshTestResult> testSshConnection({
    required SshTunnelConfig config,
    required SshTunnelSecrets secrets,
    String? testRemoteHost,
    int? testRemotePort,
  }) async {
    if (!config.enabled) {
      return const SshTestResult(ok: true, message: 'SSH Tunneling disabled');
    }
    if (config.host.trim().isEmpty) {
      return const SshTestResult(
        ok: false,
        error: 'SSH Bastion host cannot be empty',
      );
    }
    if (config.username.trim().isEmpty) {
      return const SshTestResult(
        ok: false,
        error: 'SSH username cannot be empty',
      );
    }

    final SSHSocket bastionSocket;
    SSHClient? jumpClient;
    SSHClient? client;

    try {
      if (config.jumpHost != null && config.jumpHost!.trim().isNotEmpty) {
        final jumpSocket = await _connect(
          config.jumpHost!.trim(),
          config.jumpPort ?? 22,
          timeout: Duration(seconds: config.connectTimeoutSeconds),
        );
        jumpClient = _buildClient(
          jumpSocket,
          username: config.jumpUsername ?? config.username,
          onPasswordRequest: () =>
              secrets.jumpPassword ?? secrets.password ?? '',
        );
        await jumpClient.authenticated;
        bastionSocket = await jumpClient.forwardLocal(
          config.host.trim(),
          config.port,
        );
      } else {
        bastionSocket = await _connect(
          config.host.trim(),
          config.port,
          timeout: Duration(seconds: config.connectTimeoutSeconds),
        );
      }

      List<SSHKeyPair> identities = [];
      if (config.authType == SshAuthType.privateKey) {
        String? keyContent = secrets.privateKey;
        if ((keyContent == null || keyContent.isEmpty) &&
            config.privateKeyPath != null &&
            config.privateKeyPath!.trim().isNotEmpty) {
          final file = File(config.privateKeyPath!.trim());
          if (await file.exists()) {
            keyContent = await file.readAsString();
          }
        }
        if (keyContent != null && keyContent.isNotEmpty) {
          identities = SSHKeyPair.fromPem(
            keyContent,
            secrets.passphrase,
          );
        }
      }

      String? observedFingerprint;
      client = _buildClient(
        bastionSocket,
        username: config.username.trim(),
        onPasswordRequest: () => secrets.password ?? '',
        identities: identities.isNotEmpty ? identities : null,
        onVerifyHostKey: (type, fingerprint) async {
          observedFingerprint = formatFingerprint(fingerprint);
          return true;
        },
      );

      await client.authenticated;

      // If remote host/port provided, test port forward channel
      if (testRemoteHost != null &&
          testRemoteHost.trim().isNotEmpty &&
          testRemotePort != null &&
          testRemotePort > 0) {
        try {
          final forward = await client.forwardLocal(
            testRemoteHost.trim(),
            testRemotePort,
          );
          unawaited(forward.close());
        } catch (e) {
          return SshTestResult(
            ok: false,
            error:
                'Bastion authenticated, but cannot reach target $testRemoteHost:$testRemotePort: $e',
            serverFingerprint: observedFingerprint,
          );
        }
      }

      return SshTestResult(
        ok: true,
        message: 'SSH Bastion connection successful!',
        serverFingerprint: observedFingerprint,
      );
    } catch (e) {
      return SshTestResult(
        ok: false,
        error: 'SSH Connection failed: $e',
      );
    } finally {
      unawaited(client?.close());
      unawaited(jumpClient?.close());
    }
  }
}

class SshAuthenticationException implements Exception {
  const SshAuthenticationException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The SSH server could not be reached or the session broke before any
/// credential was judged: refused, timed out, reset, a protocol error.
class SshConnectionException implements Exception {
  const SshConnectionException(this.message);
  final String message;
  @override
  String toString() => message;
}

class SshHostKeyMismatchException implements Exception {
  const SshHostKeyMismatchException(this.message);
  final String message;
  @override
  String toString() => message;
}
