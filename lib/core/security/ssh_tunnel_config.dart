import 'dart:convert';
import 'package:flutter/foundation.dart';

/// Authentication method for the SSH Bastion host.
enum SshAuthType {
  password,
  privateKey,
  sshAgent,
}

/// Non-secret configuration for connecting through an SSH Bastion / Jump Host.
@immutable
class SshTunnelConfig {
  const SshTunnelConfig({
    this.enabled = false,
    this.host = '',
    this.port = 22,
    this.username = '',
    this.authType = SshAuthType.password,
    this.privateKeyPath,
    this.knownHostFingerprint,
    this.keepAliveIntervalSeconds = 30,
    this.connectTimeoutSeconds = 15,
    this.jumpHost,
    this.jumpPort,
    this.jumpUsername,
  });

  /// Whether SSH tunneling is enabled for this connection.
  final bool enabled;

  /// Bastion / SSH server hostname or IP address.
  final String host;

  /// Bastion SSH port (defaults to 22).
  final int port;

  /// SSH login username (e.g. 'ubuntu', 'root', 'ec2-user').
  final String username;

  /// Authentication method (Password, Private Key, or SSH Agent).
  final SshAuthType authType;

  /// Optional path to an SSH private key file on the local disk.
  final String? privateKeyPath;

  /// Expected SHA-256 host key fingerprint for host verification (MitM prevention).
  /// If null or empty, host key is accepted upon first use (TOFU).
  final String? knownHostFingerprint;

  /// Keep-alive ping interval in seconds to keep NAT/firewall sessions alive.
  final int keepAliveIntervalSeconds;

  /// Connection timeout in seconds.
  final int connectTimeoutSeconds;

  /// Optional second-hop Jump Host / ProxyJump host.
  final String? jumpHost;
  final int? jumpPort;
  final String? jumpUsername;

  /// True if minimal required fields to connect are filled out.
  bool get isValid =>
      !enabled || (host.trim().isNotEmpty && username.trim().isNotEmpty && port > 0);

  SshTunnelConfig copyWith({
    bool? enabled,
    String? host,
    int? port,
    String? username,
    SshAuthType? authType,
    String? privateKeyPath,
    String? knownHostFingerprint,
    int? keepAliveIntervalSeconds,
    int? connectTimeoutSeconds,
    String? jumpHost,
    int? jumpPort,
    String? jumpUsername,
  }) {
    return SshTunnelConfig(
      enabled: enabled ?? this.enabled,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      authType: authType ?? this.authType,
      privateKeyPath: privateKeyPath ?? this.privateKeyPath,
      knownHostFingerprint: knownHostFingerprint ?? this.knownHostFingerprint,
      keepAliveIntervalSeconds:
          keepAliveIntervalSeconds ?? this.keepAliveIntervalSeconds,
      connectTimeoutSeconds:
          connectTimeoutSeconds ?? this.connectTimeoutSeconds,
      jumpHost: jumpHost ?? this.jumpHost,
      jumpPort: jumpPort ?? this.jumpPort,
      jumpUsername: jumpUsername ?? this.jumpUsername,
    );
  }

  Map<String, dynamic> toMap() => {
        'enabled': enabled,
        'host': host,
        'port': port,
        'username': username,
        'auth_type': authType.name,
        'private_key_path': privateKeyPath,
        'known_host_fingerprint': knownHostFingerprint,
        'keep_alive_seconds': keepAliveIntervalSeconds,
        'connect_timeout_seconds': connectTimeoutSeconds,
        if (jumpHost != null) 'jump_host': jumpHost,
        if (jumpPort != null) 'jump_port': jumpPort,
        if (jumpUsername != null) 'jump_username': jumpUsername,
      };

  String toJson() => jsonEncode(toMap());

  static SshTunnelConfig fromMap(Map<String, dynamic>? m) {
    if (m == null) return const SshTunnelConfig();
    return SshTunnelConfig(
      enabled: m['enabled'] as bool? ?? false,
      host: m['host'] as String? ?? '',
      port: (m['port'] as num?)?.toInt() ?? 22,
      username: m['username'] as String? ?? '',
      authType: SshAuthType.values.firstWhere(
        (e) => e.name == (m['auth_type'] as String?),
        orElse: () => SshAuthType.password,
      ),
      privateKeyPath: m['private_key_path'] as String?,
      knownHostFingerprint: m['known_host_fingerprint'] as String?,
      keepAliveIntervalSeconds:
          (m['keep_alive_seconds'] as num?)?.toInt() ?? 30,
      connectTimeoutSeconds:
          (m['connect_timeout_seconds'] as num?)?.toInt() ?? 15,
      jumpHost: m['jump_host'] as String?,
      jumpPort: (m['jump_port'] as num?)?.toInt(),
      jumpUsername: m['jump_username'] as String?,
    );
  }

  static SshTunnelConfig? fromJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return fromMap(decoded);
      }
    } catch (_) {}
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SshTunnelConfig &&
          runtimeType == other.runtimeType &&
          enabled == other.enabled &&
          host == other.host &&
          port == other.port &&
          username == other.username &&
          authType == other.authType &&
          privateKeyPath == other.privateKeyPath &&
          knownHostFingerprint == other.knownHostFingerprint &&
          keepAliveIntervalSeconds == other.keepAliveIntervalSeconds &&
          connectTimeoutSeconds == other.connectTimeoutSeconds &&
          jumpHost == other.jumpHost &&
          jumpPort == other.jumpPort &&
          jumpUsername == other.jumpUsername;

  @override
  int get hashCode => Object.hash(
        enabled,
        host,
        port,
        username,
        authType,
        privateKeyPath,
        knownHostFingerprint,
        keepAliveIntervalSeconds,
        connectTimeoutSeconds,
        jumpHost,
        jumpPort,
        jumpUsername,
      );
}

/// Sensitive credentials for SSH authentication.
/// Stored in OS secure store (Keychain / Credential Manager / libsecret)
/// and NEVER stored in the plain SQLite database.
class SshTunnelSecrets {
  SshTunnelSecrets({
    this.password,
    this.privateKey,
    this.passphrase,
    this.jumpPassword,
  });

  String? password;
  String? privateKey;
  String? passphrase;
  String? jumpPassword;

  bool get isEmpty =>
      (password == null || password!.isEmpty) &&
      (privateKey == null || privateKey!.isEmpty) &&
      (passphrase == null || passphrase!.isEmpty) &&
      (jumpPassword == null || jumpPassword!.isEmpty);

  bool get isNotEmpty => !isEmpty;

  bool get hasAny => !isEmpty;

  /// An independent copy: opening a tunnel clears the secrets it is given.
  SshTunnelSecrets copy() => SshTunnelSecrets(
        password: password,
        privateKey: privateKey,
        passphrase: passphrase,
        jumpPassword: jumpPassword,
      );

  /// Overwrites in-memory secret buffers once authentication completes.
  void zero() {
    password = null;
    privateKey = null;
    passphrase = null;
    jumpPassword = null;
  }
}
