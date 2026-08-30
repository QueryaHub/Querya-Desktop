import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/extension_support.dart';
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_driver_capabilities.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_object_metadata.dart';
import 'package:querya_desktop/core/extensions/models/extension_server_stats.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_bridge.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_os_isolation.dart';
import 'package:querya_desktop/core/extensions/sandbox/unsandboxed_launch_consent_gate.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/storage/connection_secrets_store.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Owns [PluginRpcBridge] sessions for extension-backed connections.
class ExtensionDriverSession {
  ExtensionDriverSession._();
  static final ExtensionDriverSession instance = ExtensionDriverSession._();

  final Map<int, PluginRpcBridge> _bridges = {};
  final Map<int, ExtensionManifest> _manifests = {};

  /// Test/DI override for bridge creation.
  PluginRpcBridge Function()? bridgeFactory;

  bool isConnected(int connectionId) =>
      _bridges[connectionId]?.isStarted == true;

  /// Starts the plugin (if needed), injects credentials, and calls `db.connect`.
  Future<PluginRpcBridge> ensureConnected(ConnectionRow row) async {
    final id = row.id;
    if (id == null) {
      throw StateError('ConnectionRow.id is required for extension drivers');
    }
    if (!ExtensionDriverCatalog.isExtensionDriverConnection(row)) {
      throw StateError(
        'Connection "${row.name}" is not backed by an installed extension driver',
      );
    }

    final existing = _bridges[id];
    if (existing != null && existing.isStarted) {
      return existing;
    }

    final manifest = await _resolveManifestForRow(row);
    final hydrated = await _hydrateSecrets(row);
    late final PluginRpcBridge bridge;
    bridge = await _startBridge(
      manifest,
      onProcessExited: (code) {
        if (_bridges[id] == bridge) {
          _bridges.remove(id);
          _manifests.remove(id);
        }
      },
    );

    try {
      await _injectAndConnect(bridge, connectionId: id, row: hydrated);
    } catch (e) {
      try {
        await bridge.shutdown();
      } catch (_) {}
      rethrow;
    }

    _bridges[id] = bridge;
    _manifests[id] = manifest;
    return bridge;
  }

  /// One-shot connectivity check: spawns a temporary plugin process,
  /// connects, and tears everything down. Returns the reported server version.
  Future<String> testConnection({
    required ExtensionManifest manifest,
    required ConnectionRow row,
  }) async {
    // Ephemeral positive id — never stored, only used for this RPC round-trip.
    final tempId =
        DateTime.now().millisecondsSinceEpoch & 0x7fffffff | 0x40000000;
    final bridge = await _startBridge(manifest);
    try {
      final result = await _injectAndConnect(
        bridge,
        connectionId: tempId,
        row: row,
      );
      String version = '';
      if (result is Map) {
        version = '${result['serverVersion'] ?? ''}';
      }
      try {
        await bridge.sendRequest('db.disconnect', {'connectionId': tempId});
      } catch (_) {}
      return version;
    } finally {
      try {
        await bridge.shutdown();
      } catch (_) {}
    }
  }

  Future<PluginRpcBridge> _startBridge(
    ExtensionManifest manifest, {
    void Function(int code)? onProcessExited,
  }) async {
    final root = manifest.installPath;
    if (root == null || root.isEmpty) {
      throw StateError('Extension "${manifest.id}" has no install path');
    }
    final main = manifest.main?.trim();
    if (main == null || main.isEmpty) {
      throw StateError('Extension "${manifest.id}" is missing main entry');
    }
    final executable = p.join(root, main);
    final entryFile = File(executable);
    if (!entryFile.existsSync()) {
      throw StateError('Driver entry not found: $executable');
    }
    final canExecute = await entryFile
        .stat()
        .then((s) => s.mode & 0x111 != 0, onError: (_) => true);
    if (!canExecute) {
      try {
        await ExtensionSupport.markExecutableIfExists(entryFile);
      } catch (e) {
        throw StateError(
          'Driver entry is not executable: $executable. '
          'Reinstall the extension package ($e).',
        );
      }
    }

    final manifestTimeoutSeconds =
        manifest.sandbox?.resources.timeoutSeconds;
    final bridge = bridgeFactory?.call() ??
        PluginRpcBridge(
          requestTimeout:
              manifestTimeoutSeconds != null && manifestTimeoutSeconds > 0
                  ? Duration(seconds: manifestTimeoutSeconds)
                  : const Duration(seconds: 60),
          onProcessExited: onProcessExited,
        );
    await _startBridgeWithConsent(
      bridge: bridge,
      manifest: manifest,
      pluginExecutable: executable,
      extensionRoot: root,
    );
    return bridge;
  }

  Future<void> _startBridgeWithConsent({
    required PluginRpcBridge bridge,
    required ExtensionManifest manifest,
    required String pluginExecutable,
    required String extensionRoot,
  }) async {
    const handshakeParams = {
      'queryaVersion': '2.0.0',
    };

    try {
      await bridge.start(
        manifest: manifest,
        pluginExecutable: pluginExecutable,
        extensionRoot: extensionRoot,
        handshakeParams: {
          ...handshakeParams,
          'pluginId': manifest.id,
        },
      );
    } on SandboxOsIsolationUnavailableException catch (error) {
      final approved =
          await UnsandboxedLaunchConsentGate.instance.request(error);
      if (!approved) rethrow;
      await bridge.start(
        manifest: manifest,
        pluginExecutable: pluginExecutable,
        extensionRoot: extensionRoot,
        allowUnsandboxedLaunch: true,
        handshakeParams: {
          ...handshakeParams,
          'pluginId': manifest.id,
        },
      );
    }
  }

  Future<Object?> _injectAndConnect(
    PluginRpcBridge bridge, {
    required int connectionId,
    required ConnectionRow row,
  }) async {
    final options = _decodeOptions(row.driverOptions);
    final safeMode = options.remove('safe_mode') ?? options.remove('safeMode');
    options.remove('sslMode');

    await bridge.injectCredentials({
      'connectionId': connectionId,
      if (row.password != null && row.password!.isNotEmpty)
        'password': row.password,
    });

    return bridge.connect(
      buildExtensionConnectParams(
        connectionId: connectionId,
        row: row,
        options: options,
        safeMode: safeMode,
      ),
    );
  }

  /// Builds `db.connect` params including HTTPS when [ConnectionRow.useSSL] is set.
  static Map<String, Object?> buildExtensionConnectParams({
    required int connectionId,
    required ConnectionRow row,
    Map<String, Object?> options = const {},
    Object? safeMode,
  }) {
    final host = row.host?.trim();
    final port = row.port ?? 8123;
    final database = row.databaseName?.trim().isNotEmpty == true
        ? row.databaseName!.trim()
        : 'default';

    final params = <String, Object?>{
      'connectionId': connectionId,
      if (row.username != null && row.username!.isNotEmpty) 'user': row.username,
      'database': database,
      ...options,
      if (safeMode != null) 'safeMode': safeMode,
    };

    if (host != null && host.isNotEmpty) {
      final scheme = row.useSSL ? 'https' : 'http';
      params['connectionString'] = '$scheme://$host:$port/$database';
    } else {
      if (row.port != null) params['port'] = row.port;
      if (host != null && host.isNotEmpty) params['host'] = host;
    }

    return params;
  }

  Future<ConnectionRow> _hydrateSecrets(ConnectionRow row) async {
    final id = row.id;
    if (id == null) return row;
    if ((row.password != null && row.password!.isNotEmpty) ||
        (row.connectionString != null && row.connectionString!.isNotEmpty)) {
      return row;
    }
    final secrets = await ConnectionSecretsStore.readForConnection(id);
    if (secrets.password == null && secrets.connectionString == null) {
      return row;
    }
    return ConnectionRow(
      id: row.id,
      type: row.type,
      name: row.name,
      host: row.host,
      port: row.port,
      username: row.username,
      password: secrets.password ?? row.password,
      databaseName: row.databaseName,
      authSource: row.authSource,
      useSSL: row.useSSL,
      connectionString: secrets.connectionString ?? row.connectionString,
      extensionId: row.extensionId,
      driverOptions: row.driverOptions,
      folderId: row.folderId,
      sortOrder: row.sortOrder,
      createdAt: row.createdAt,
    );
  }

  Future<ExtensionManifest> _resolveManifestForRow(ConnectionRow row) async {
    await LocalExtensionRegistry.instance.load();
    final manifest = ExtensionDriverCatalog.manifestForConnection(row);
    if (manifest != null) return manifest;
    final extId = row.extensionId?.trim();
    if (extId != null && extId.isNotEmpty) {
      throw StateError(
        'Extension "$extId" is not installed. Reinstall the package.',
      );
    }
    throw StateError(
      'No extension driver is installed for connection type "${row.type}".',
    );
  }

  /// Executes SQL through the plugin (`db.query`) and returns the raw result.
  ///
  /// When [limit] is omitted, Preferences **Max rows in results** is sent so
  /// drivers can bound the NDJSON response before it hits the host.
  Future<ExtensionQueryResult> query(
    ConnectionRow row,
    String sql, {
    int? limit,
  }) async {
    final bridge = await ensureConnected(row);
    final effectiveLimit =
        limit ?? await AppSettings.instance.getSqlResultMaxRows();
    final result = await bridge.sendRequest('db.query', {
      'connectionId': row.id,
      'sql': sql,
      'limit': effectiveLimit,
    });
    return compute(_parseExtensionQueryResultRpc, result);
  }

  Future<SduiTreeSchema> getSchemaTree(ConnectionRow row) async {
    final bridge = await ensureConnected(row);
    final result = await bridge.sendRequest('db.getSchemaTree', {
      'connectionId': row.id,
    });
    return _treeSchemaFromResult(result);
  }

  Future<List<SduiTreeNode>> expandTreeNode(
    ConnectionRow row,
    String nodeId,
  ) async {
    final bridge = await ensureConnected(row);
    final result = await bridge.sendRequest('db.expandTreeNode', {
      'connectionId': row.id,
      'nodeId': nodeId,
    });
    return _nodesFromResult(result);
  }

  Future<ExtensionDriverCapabilities> getCapabilities(ConnectionRow row) async {
    final bridge = await ensureConnected(row);
    try {
      final result = await bridge.sendRequest('db.getCapabilities', {
        'connectionId': row.id,
      });
      return ExtensionDriverCapabilities.fromRpc(result);
    } catch (e) {
      debugPrint('ExtensionDriverSession getCapabilities fallback ($e)');
      return const ExtensionDriverCapabilities();
    }
  }

  Future<ExtensionServerStats> getServerStats(ConnectionRow row) async {
    final bridge = await ensureConnected(row);
    try {
      final result = await bridge.sendRequest('db.getServerStats', {
        'connectionId': row.id,
      });
      return ExtensionServerStats.fromRpc(result);
    } catch (e) {
      debugPrint('ExtensionDriverSession getServerStats fallback ($e)');
      return const ExtensionServerStats();
    }
  }

  Future<ExtensionObjectMetadata> getObjectMetadata(
    ConnectionRow row, {
    required String nodeId,
    required String nodeType,
  }) async {
    final bridge = await ensureConnected(row);
    try {
      final result = await bridge.sendRequest('db.getObjectMetadata', {
        'connectionId': row.id,
        'nodeId': nodeId,
        'nodeType': nodeType,
      });
      return ExtensionObjectMetadata.fromRpc(result);
    } catch (e) {
      debugPrint('ExtensionDriverSession getObjectMetadata fallback ($e)');
      return ExtensionObjectMetadata(nodeId: nodeId, nodeType: nodeType);
    }
  }

  Future<bool> cancelQuery(ConnectionRow row, {required String queryId}) async {
    final bridge = await ensureConnected(row);
    try {
      final result = await bridge.sendRequest('db.cancelQuery', {
        'connectionId': row.id,
        'queryId': queryId,
      });
      if (result is Map) {
        return result['success'] == true || result['cancelled'] == true;
      }
      return true;
    } catch (e) {
      debugPrint('ExtensionDriverSession cancelQuery failed ($e)');
      return false;
    }
  }

  /// Queries table schema metadata (column types, nullability, PKs) via `db.getTableSchema`.
  Future<TableSchemaMeta> getTableSchema(
    ConnectionRow row, {
    required String database,
    String? schema,
    required String tableName,
  }) async {
    final bridge = await ensureConnected(row);
    try {
      final result = await bridge.sendRequest('db.getTableSchema', {
        'connectionId': row.id,
        'database': database,
        if (schema != null && schema.isNotEmpty) 'schema': schema,
        'tableName': tableName,
      });
      if (result is Map) {
        return TableSchemaMeta.fromJson(Map<String, dynamic>.from(result));
      }
      return TableSchemaMeta(tableName: tableName, schema: schema);
    } catch (e) {
      debugPrint('ExtensionDriverSession getTableSchema fallback ($e)');
      return TableSchemaMeta(tableName: tableName, schema: schema);
    }
  }

  /// Executes batch data mutations (insert, update, delete) via `db.mutate`.
  Future<Map<String, dynamic>> mutate(
    ConnectionRow row, {
    required String database,
    String? schema,
    required String tableName,
    required List<Map<String, dynamic>> mutations,
  }) async {
    final bridge = await ensureConnected(row);
    final result = await bridge.sendRequest('db.mutate', {
      'connectionId': row.id,
      'database': database,
      if (schema != null && schema.isNotEmpty) 'schema': schema,
      'tableName': tableName,
      'mutations': mutations,
    });
    if (result is Map) {
      return Map<String, dynamic>.from(result);
    }
    return {'success': true, 'affectedRows': mutations.length};
  }

  Future<void> disconnect(int connectionId) async {
    final bridge = _bridges.remove(connectionId);
    _manifests.remove(connectionId);
    if (bridge == null) return;
    try {
      await bridge.sendRequest('db.disconnect', {
        'connectionId': connectionId,
      });
    } catch (e) {
      debugPrint('ExtensionDriverSession db.disconnect: $e');
    }
    try {
      await bridge.shutdown();
    } catch (e) {
      debugPrint('ExtensionDriverSession shutdown: $e');
    }
  }

  /// Restarts the extension driver process for [row] by cleanly disconnecting
  /// the active bridge and re-establishing the connection.
  Future<PluginRpcBridge> restart(ConnectionRow row) async {
    final id = row.id;
    if (id != null) {
      await disconnect(id);
    }
    return ensureConnected(row);
  }

  Future<void> disconnectAll() async {
    final ids = _bridges.keys.toList();
    for (final id in ids) {
      await disconnect(id);
    }
  }

  Map<String, Object?> _decodeOptions(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, Object?>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((k, v) => MapEntry('$k', v));
      }
    } catch (e) {
      debugPrint('ExtensionDriverSession: bad driver_options: $e');
    }
    return {};
  }

  SduiTreeSchema _treeSchemaFromResult(Object? result) {
    if (result is Map<String, dynamic>) {
      return SduiTreeSchema.fromJson(result);
    }
    if (result is Map) {
      return SduiTreeSchema.fromJson(Map<String, dynamic>.from(result));
    }
    if (result is List) {
      return SduiTreeSchema.fromJson({'nodes': result});
    }
    return const SduiTreeSchema();
  }

  List<SduiTreeNode> _nodesFromResult(Object? result) {
    if (result is Map) {
      final map = result is Map<String, dynamic>
          ? result
          : Map<String, dynamic>.from(result);
      final schema = SduiTreeSchema.fromJson(map);
      if (schema.roots.isNotEmpty) return schema.roots;
      final children = map['children'] ?? map['nodes'];
      if (children is List) {
        return [
          for (final item in children)
            if (item is Map<String, dynamic>)
              SduiTreeNode.fromJson(item)
            else if (item is Map)
              SduiTreeNode.fromJson(Map<String, dynamic>.from(item)),
        ];
      }
    }
    if (result is List) {
      return [
        for (final item in result)
          if (item is Map<String, dynamic>)
            SduiTreeNode.fromJson(item)
          else if (item is Map)
            SduiTreeNode.fromJson(Map<String, dynamic>.from(item)),
      ];
    }
    return const [];
  }
}

/// Normalized tabular result of `db.query` from an extension driver.
class ExtensionQueryResult {
  const ExtensionQueryResult({
    this.columns = const [],
    this.rows = const [],
    this.message,
    this.elapsedMs,
    this.queryId,
  });

  /// Column names in order.
  final List<String> columns;

  /// Row values converted to display strings (`NULL` for null).
  final List<List<String>> rows;

  /// Status message for non-tabular commands.
  final String? message;
  final int? elapsedMs;
  final String? queryId;

  factory ExtensionQueryResult.fromRpc(Object? raw) {
    if (raw is! Map) return const ExtensionQueryResult();
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);

    final columns = <String>[];
    final columnsRaw = map['columns'];
    if (columnsRaw is List) {
      for (final col in columnsRaw) {
        if (col is Map) {
          columns.add('${col['name'] ?? col['label'] ?? ''}');
        } else if (col != null) {
          columns.add('$col');
        }
      }
    }

    final rows = <List<String>>[];
    final rowsRaw = map['rows'];
    if (rowsRaw is List) {
      for (final row in rowsRaw) {
        if (row is List) {
          rows.add([
            for (final cell in row) cell == null ? 'NULL' : '$cell',
          ]);
        }
      }
    }

    int? elapsedMs;
    final stats = map['statistics'];
    if (stats is Map) {
      final elapsed = stats['elapsedMs'] ?? stats['elapsed_ms'];
      if (elapsed is num) elapsedMs = elapsed.toInt();
    }
    final execTime = map['executionTimeMs'];
    if (elapsedMs == null && execTime is num) elapsedMs = execTime.toInt();

    return ExtensionQueryResult(
      columns: columns,
      rows: rows,
      message: map['message'] as String?,
      elapsedMs: elapsedMs,
      queryId: map['queryId']?.toString(),
    );
  }
}

ExtensionQueryResult _parseExtensionQueryResultRpc(Object? raw) {
  return ExtensionQueryResult.fromRpc(raw);
}
