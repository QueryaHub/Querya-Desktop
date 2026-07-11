import 'dart:convert';
import 'dart:typed_data';

import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';

/// Mutable UTF-8 buffer that can be zeroed after use (Block E §5).
///
/// Dart [String] values are immutable and cannot be wiped; keep secrets in
/// [SensitiveUtf8Buffer] while assembling RPC payloads, then [clear].
class SensitiveUtf8Buffer {
  SensitiveUtf8Buffer(String value) : _bytes = Uint8List.fromList(utf8.encode(value));

  Uint8List? _bytes;

  bool get isCleared => _bytes == null;

  String? get asString {
    final bytes = _bytes;
    if (bytes == null) return null;
    return utf8.decode(bytes);
  }

  /// Overwrites the buffer with zeros and drops the reference.
  void clear() {
    final bytes = _bytes;
    if (bytes == null) return;
    bytes.fillRange(0, bytes.length, 0);
    _bytes = null;
  }
}

/// Loads connection secrets from the OS store and injects them into a sandboxed
/// plugin process exclusively via Stdio JSON-RPC (never argv / env).
class SandboxCredentialsInjector {
  SandboxCredentialsInjector({
    this.requestTimeout = const Duration(seconds: 10),
    Future<({String? password, String? connectionString})> Function(int connectionId)?
        secretsReader,
    JsonRpcStdioClient Function(SandboxProcessHandle handle)? clientFactory,
  })  : _secretsReader = secretsReader ?? ConnectionSecretsStore.readForConnection,
        _clientFactory = clientFactory;

  final Duration requestTimeout;
  final Future<({String? password, String? connectionString})> Function(
    int connectionId,
  ) _secretsReader;
  final JsonRpcStdioClient Function(SandboxProcessHandle handle)? _clientFactory;

  /// Reads secrets for [connectionId] and sends `system.injectCredentials`.
  ///
  /// Returns the RPC result map (or null). Sensitive buffers are cleared in a
  /// `finally` block regardless of success or failure.
  Future<Object?> injectCredentials({
    required SandboxProcessHandle handle,
    required int connectionId,
    Map<String, Object?> extraParams = const {},
  }) async {
    final secrets = await _secretsReader(connectionId);
    final passwordBuf =
        secrets.password != null ? SensitiveUtf8Buffer(secrets.password!) : null;
    final connectionStringBuf = secrets.connectionString != null
        ? SensitiveUtf8Buffer(secrets.connectionString!)
        : null;

    final client = _clientFactory?.call(handle) ??
        JsonRpcStdioClient(
          stdout: handle.process.stdout,
          stdin: handle.process.stdin,
          requestTimeout: requestTimeout,
        );
    final ownsClient = _clientFactory == null;

    try {
      final params = <String, Object?>{
        'connectionId': connectionId,
        if (passwordBuf?.asString != null) 'password': passwordBuf!.asString,
        if (connectionStringBuf?.asString != null)
          'connectionString': connectionStringBuf!.asString,
        ...extraParams,
      };
      return await client.sendRequest('system.injectCredentials', params);
    } finally {
      passwordBuf?.clear();
      connectionStringBuf?.clear();
      if (ownsClient) {
        await client.close();
      }
    }
  }

  /// Reads secrets and sends `db.connect` with host/port plus credentials.
  Future<Object?> connect({
    required SandboxProcessHandle handle,
    required int connectionId,
    required String host,
    required int port,
    String? database,
    String? username,
    bool ssl = false,
    Map<String, Object?> extraParams = const {},
  }) async {
    final secrets = await _secretsReader(connectionId);
    final passwordBuf =
        secrets.password != null ? SensitiveUtf8Buffer(secrets.password!) : null;
    final connectionStringBuf = secrets.connectionString != null
        ? SensitiveUtf8Buffer(secrets.connectionString!)
        : null;

    final client = _clientFactory?.call(handle) ??
        JsonRpcStdioClient(
          stdout: handle.process.stdout,
          stdin: handle.process.stdin,
          requestTimeout: requestTimeout,
        );
    final ownsClient = _clientFactory == null;

    try {
      final params = <String, Object?>{
        'connectionId': connectionId,
        'host': host,
        'port': port,
        if (database != null) 'database': database,
        if (username != null) 'username': username,
        'ssl': ssl,
        if (passwordBuf?.asString != null) 'password': passwordBuf!.asString,
        if (connectionStringBuf?.asString != null)
          'connectionString': connectionStringBuf!.asString,
        ...extraParams,
      };
      return await client.sendRequest('db.connect', params);
    } finally {
      passwordBuf?.clear();
      connectionStringBuf?.clear();
      if (ownsClient) {
        await client.close();
      }
    }
  }
}
