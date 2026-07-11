import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_bridge.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
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
    final extensionId = row.extensionId?.trim();
    if (extensionId == null || extensionId.isEmpty) {
      throw StateError('ConnectionRow.extensionId is required');
    }

    final existing = _bridges[id];
    if (existing != null && existing.isStarted) {
      return existing;
    }

    final manifest = await _resolveManifest(extensionId);
    final root = manifest.installPath;
    if (root == null || root.isEmpty) {
      throw StateError('Extension "$extensionId" has no install path');
    }
    final main = manifest.main?.trim();
    if (main == null || main.isEmpty) {
      throw StateError('Extension "$extensionId" is missing main entry');
    }
    final executable = p.join(root, main);
    if (!File(executable).existsSync()) {
      throw StateError('Driver entry not found: $executable');
    }

    final bridge = bridgeFactory?.call() ?? PluginRpcBridge();
    await bridge.start(
      manifest: manifest,
      pluginExecutable: executable,
      extensionRoot: root,
      handshakeParams: {
        'queryaVersion': '2.0.0',
        'pluginId': manifest.id,
      },
    );

    final options = _decodeOptions(row.driverOptions);
    await bridge.injectCredentials({
      'connectionId': id,
      if (row.password != null && row.password!.isNotEmpty)
        'password': row.password,
      ...options,
    });

    final connectParams = <String, Object?>{
      'connectionId': id,
      if (row.host != null) 'host': row.host,
      if (row.port != null) 'port': row.port,
      if (row.username != null) 'user': row.username,
      if (row.databaseName != null) 'database': row.databaseName,
      if (options.containsKey('safe_mode')) 'safeMode': options['safe_mode'],
      if (options.containsKey('safeMode')) 'safeMode': options['safeMode'],
      ...options,
    };
    await bridge.connect(connectParams);

    _bridges[id] = bridge;
    _manifests[id] = manifest;
    return bridge;
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

  Future<void> disconnectAll() async {
    final ids = _bridges.keys.toList();
    for (final id in ids) {
      await disconnect(id);
    }
  }

  Future<ExtensionManifest> _resolveManifest(String extensionId) async {
    await LocalExtensionRegistry.instance.load();
    final match = LocalExtensionRegistry.instance.manifests
        .where((m) => m.id == extensionId)
        .toList();
    if (match.isEmpty) {
      throw StateError(
        'Extension "$extensionId" is not installed. Reinstall the package.',
      );
    }
    return match.first;
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
