import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:querya_desktop/core/mcp/mcp_endpoint.dart';
import 'package:querya_desktop/core/mcp/mcp_query_service.dart';
import 'package:querya_desktop/core/mcp/mcp_socket_host.dart';
import 'package:querya_desktop/core/mcp/mcp_sql_delegates.dart';
import 'package:querya_desktop/core/mcp/querya_mcp_server.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Owns the in-app MCP server: starts it when enabled in settings, stops it
/// on shutdown, and reports status and tool calls to the UI.
class McpServerController {
  McpServerController({
    McpQueryService? service,
    File? endpointFile,
    String? version,
  })  : _service = service ??
            McpQueryService(createDelegate: createReadOnlyMcpDelegate),
        _endpointFile = endpointFile ?? McpEndpoint.defaultFile(),
        _versionOverride = version;

  static final McpServerController instance = McpServerController();

  /// `app_settings` key; the server is off unless the user enables it.
  static const enabledKey = 'mcp_server_enabled';

  final McpQueryService _service;
  final File _endpointFile;
  final String? _versionOverride;

  Future<String> _version() async {
    if (_versionOverride != null) return _versionOverride;
    try {
      return (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      return 'unknown';
    }
  }

  McpSocketHost? _host;
  final _servers = <QueryaMcpServer>{};

  /// Running state and client count, for the settings page.
  final status = ValueNotifier<McpServerStatus>(McpServerStatus.stopped);

  final _calls = StreamController<McpCallRecord>.broadcast();

  /// Every finished tool call (activity log, audit).
  Stream<McpCallRecord> get calls => _calls.stream;

  File get endpointFile => _endpointFile;

  Future<bool> isEnabled() async {
    final v = await LocalDb.instance.getAppSetting(enabledKey);
    return v == 'true';
  }

  Future<void> setEnabled(bool enabled) async {
    await LocalDb.instance.setAppSetting(enabledKey, enabled.toString());
    enabled ? await start() : await stop();
  }

  /// Called once at startup.
  Future<void> startIfEnabled() async {
    try {
      if (await isEnabled()) await start();
    } catch (e) {
      debugPrint('MCP server did not start: $e');
      status.value = McpServerStatus.failed(e.toString());
    }
  }

  Future<void> start() async {
    if (_host != null) return;
    final version = await _version();
    final host = McpSocketHost(
      endpointFile: _endpointFile,
      version: version,
      onSession: (channel) async {
        final server = QueryaMcpServer(
          channel,
          service: _service,
          version: version,
          onCall: _calls.add,
        );
        _servers.add(server);
        await server.done;
        _servers.remove(server);
      },
    );
    host.changes.listen((_) => _publish(host));
    await host.start();
    _host = host;
    _publish(host);
  }

  /// Disconnects clients and removes the endpoint file.
  Future<void> stop() async {
    final host = _host;
    _host = null;
    for (final s in _servers.toList()) {
      await s.shutdown();
    }
    _servers.clear();
    await host?.stop();
    status.value = McpServerStatus.stopped;
  }

  void _publish(McpSocketHost host) {
    if (_host != host && _host != null) return;
    status.value = host.isRunning
        ? McpServerStatus(
            running: true, port: host.port, clients: host.sessionCount)
        : McpServerStatus.stopped;
  }
}

@immutable
class McpServerStatus {
  const McpServerStatus({
    required this.running,
    this.port,
    this.clients = 0,
    this.error,
  });

  const McpServerStatus.failed(String this.error)
      : running = false,
        port = null,
        clients = 0;

  static const stopped = McpServerStatus(running: false);

  final bool running;
  final int? port;
  final int clients;
  final String? error;

  @override
  bool operator ==(Object other) =>
      other is McpServerStatus &&
      other.running == running &&
      other.port == port &&
      other.clients == clients &&
      other.error == error;

  @override
  int get hashCode => Object.hash(running, port, clients, error);
}
