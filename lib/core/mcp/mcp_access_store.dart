import 'dart:convert';

import 'package:querya_desktop/core/storage/local_db.dart';

/// Which connections MCP clients may read. Opt-in per connection: a
/// connection that was never enabled is invisible to every MCP tool.
abstract class McpAccessPolicy {
  Future<bool> canRead(ConnectionRow row);
}

/// Read and change which connections are shared (settings page).
abstract class McpAccessSettings implements McpAccessPolicy {
  Future<Set<int>> readableIds();
  Future<void> setReadable(int connectionId, bool readable);
}

/// [McpAccessPolicy] stored in `app_settings` as a JSON list of connection ids.
class McpAccessStore implements McpAccessSettings {
  McpAccessStore._();

  static final McpAccessStore instance = McpAccessStore._();

  static const settingsKey = 'mcp_read_connection_ids';

  @override
  Future<Set<int>> readableIds() async {
    final raw = await LocalDb.instance.getAppSetting(settingsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return {for (final v in decoded) if (v is int) v};
    } catch (_) {}
    return {};
  }

  @override
  Future<void> setReadable(int connectionId, bool readable) async {
    final ids = await readableIds();
    if (readable) {
      ids.add(connectionId);
    } else {
      ids.remove(connectionId);
    }
    await LocalDb.instance
        .setAppSetting(settingsKey, jsonEncode(ids.toList()..sort()));
  }

  @override
  Future<bool> canRead(ConnectionRow row) async =>
      row.id != null && (await readableIds()).contains(row.id);
}
