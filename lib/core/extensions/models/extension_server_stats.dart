/// Normalized server statistics reported by an extension driver via `db.getServerStats`.
class ExtensionServerStats {
  const ExtensionServerStats({
    this.serverVersion,
    this.uptimeSeconds,
    this.activeConnections,
    this.activeQueries,
    this.memoryUsageBytes,
    this.databaseSizes = const {},
    this.extraMetrics = const {},
  });

  /// Server engine version string (e.g. "ClickHouse 24.3.1.1").
  final String? serverVersion;

  /// Total uptime in seconds.
  final int? uptimeSeconds;

  /// Number of active client connections.
  final int? activeConnections;

  /// Number of currently running queries on the server.
  final int? activeQueries;

  /// Total memory consumption by the database process in bytes.
  final int? memoryUsageBytes;

  /// Size in bytes for each database on the server (`{"default": 1048576, ...}`).
  final Map<String, int> databaseSizes;

  /// Driver-specific extra metrics (key -> string/num value).
  final Map<String, Object?> extraMetrics;

  factory ExtensionServerStats.fromRpc(Object? raw) {
    if (raw is! Map) return const ExtensionServerStats();
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);

    final dbSizes = <String, int>{};
    final rawSizes = map['databaseSizes'] ?? map['database_sizes'];
    if (rawSizes is Map) {
      rawSizes.forEach((k, v) {
        if (v is num) dbSizes['$k'] = v.toInt();
      });
    }

    final extra = <String, Object?>{};
    final rawExtra = map['extraMetrics'] ?? map['extra_metrics'];
    if (rawExtra is Map) {
      rawExtra.forEach((k, v) {
        if (v != null) extra['$k'] = v;
      });
    }

    int? toIntOrNull(Object? val) {
      if (val is num) return val.toInt();
      if (val is String) return int.tryParse(val.trim());
      return null;
    }

    return ExtensionServerStats(
      serverVersion: map['serverVersion']?.toString() ??
          map['server_version']?.toString() ??
          map['version']?.toString(),
      uptimeSeconds: toIntOrNull(map['uptimeSeconds'] ?? map['uptime_seconds']),
      activeConnections: toIntOrNull(
          map['activeConnections'] ?? map['active_connections']),
      activeQueries:
          toIntOrNull(map['activeQueries'] ?? map['active_queries']),
      memoryUsageBytes: toIntOrNull(
          map['memoryUsageBytes'] ?? map['memory_usage_bytes']),
      databaseSizes: dbSizes,
      extraMetrics: extra,
    );
  }

  Map<String, Object?> toJson() => {
        if (serverVersion != null) 'serverVersion': serverVersion,
        if (uptimeSeconds != null) 'uptimeSeconds': uptimeSeconds,
        if (activeConnections != null) 'activeConnections': activeConnections,
        if (activeQueries != null) 'activeQueries': activeQueries,
        if (memoryUsageBytes != null) 'memoryUsageBytes': memoryUsageBytes,
        'databaseSizes': databaseSizes,
        'extraMetrics': extraMetrics,
      };
}
