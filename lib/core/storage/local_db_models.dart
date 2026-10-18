import 'dart:convert';

import 'package:querya_desktop/core/security/connection_environment.dart';
import 'package:querya_desktop/core/security/ssh_tunnel_config.dart';
import 'package:querya_desktop/core/util/log_ignored.dart';

int? sqliteInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

/// Where an audited mutation was started.
enum MutationAuditSource {
  sqlEditor('sql_editor'),
  tableEditor('table_editor');

  const MutationAuditSource(this.storageValue);

  final String storageValue;

  static MutationAuditSource fromStorageValue(String? value) =>
      values.firstWhere(
        (s) => s.storageValue == value,
        orElse: () => MutationAuditSource.sqlEditor,
      );
}

/// One row of the local mutation audit trail.
/// Rows kept in `mcp_activity`.
const kMcpActivityCap = 200;

/// One tool call made by an MCP client.
class McpActivityEntry {
  const McpActivityEntry({
    this.id,
    required this.recordedAt,
    required this.client,
    required this.tool,
    this.connectionId,
    this.connectionName,
    this.sqlText,
    this.rowCount,
    required this.durationMs,
    this.error,
    this.refusalRule,
  });

  final int? id;

  /// UTC ISO-8601.
  final String recordedAt;
  final String client;
  final String tool;
  final int? connectionId;
  final String? connectionName;
  final String? sqlText;
  final int? rowCount;
  final int durationMs;
  final String? error;

  /// The guard rule that refused the call (`read_only_only`, ...), when one did.
  final String? refusalRule;

  Map<String, Object?> toMap() => {
        'id': id,
        'recorded_at': recordedAt,
        'client': client,
        'tool': tool,
        'connection_id': connectionId,
        'connection_name': connectionName,
        'sql_text': sqlText,
        'row_count': rowCount,
        'duration_ms': durationMs,
        'error': error,
        'refusal_rule': refusalRule,
      };

  static McpActivityEntry fromMap(Map<String, Object?> m) => McpActivityEntry(
        id: sqliteInt(m['id']),
        recordedAt: m['recorded_at'] as String,
        client: m['client'] as String,
        tool: m['tool'] as String,
        connectionId: sqliteInt(m['connection_id']),
        connectionName: m['connection_name'] as String?,
        sqlText: m['sql_text'] as String?,
        rowCount: sqliteInt(m['row_count']),
        durationMs: sqliteInt(m['duration_ms']) ?? 0,
        error: m['error'] as String?,
        refusalRule: m['refusal_rule'] as String?,
      );
}

class MutationAuditEntry {
  const MutationAuditEntry({
    required this.id,
    this.connectionId,
    required this.connectionName,
    this.environment,
    this.databaseName,
    required this.sqlText,
    this.rowsAffected,
    required this.source,
    required this.recordedAt,
  });

  final int id;
  final int? connectionId;
  final String connectionName;

  /// `development` / `staging` / `production` when the connection was tagged.
  final String? environment;
  final String? databaseName;
  final String sqlText;
  final int? rowsAffected;
  final MutationAuditSource source;
  final String recordedAt;

  static MutationAuditEntry fromMap(Map<String, Object?> m) =>
      MutationAuditEntry(
        id: sqliteInt(m['id'])!,
        connectionId: sqliteInt(m['connection_id']),
        connectionName: m['connection_name'] as String,
        environment: m['environment'] as String?,
        databaseName: m['database_name'] as String?,
        sqlText: m['sql_text'] as String,
        rowsAffected: sqliteInt(m['rows_affected']),
        source: MutationAuditSource.fromStorageValue(m['source'] as String?),
        recordedAt: m['recorded_at'] as String,
      );
}

/// One row from [LocalDb.sql_query_history] (recent SQL, no secrets).
class SqlQueryHistoryEntry {
  const SqlQueryHistoryEntry({
    required this.id,
    required this.connectionId,
    this.databaseName,
    required this.sqlText,
    required this.recordedAt,
  });

  final int id;
  final int connectionId;
  final String? databaseName;
  final String sqlText;
  final String recordedAt;

  static SqlQueryHistoryEntry fromMap(Map<String, Object?> m) =>
      SqlQueryHistoryEntry(
        id: sqliteInt(m['id'])!,
        connectionId: sqliteInt(m['connection_id'])!,
        databaseName: m['database_name'] as String?,
        sqlText: m['sql_text'] as String,
        recordedAt: m['recorded_at'] as String,
      );
}

class ConnectionRow {
  const ConnectionRow({
    this.id,
    required this.type,
    required this.name,
    this.host,
    this.port,
    this.username,
    this.password,
    this.databaseName,
    this.authSource,
    this.useSSL = false,
    this.connectionString,
    this.extensionId,
    this.driverOptions,
    this.folderId,
    this.sortOrder = 0,
    required this.createdAt,
    this.sshSecrets,
    this.removeSavedPassword = false,
  });

  /// Set by an edit form (never stored): the saved password is to be removed,
  /// not kept because the password field was left blank (#1311).
  final bool removeSavedPassword;

  final int? id;
  final String type;
  final String name;
  final String? host;
  final int? port;
  final String? username;
  final String? password;
  final String? databaseName;
  final String? authSource;
  final bool useSSL;
  final String? connectionString;
  final SshTunnelSecrets? sshSecrets;

  /// Package id of an installed extension driver (null for built-ins).
  final String? extensionId;

  /// Non-secret driver-specific form values as JSON text.
  final String? driverOptions;

  final int? folderId;
  final int sortOrder;
  final String createdAt;

  /// True when this row is backed by an installed extension driver.
  bool get isExtensionDriver =>
      extensionId != null && extensionId!.trim().isNotEmpty;

  /// Returns the SSH tunnel config stored in [driverOptions], if any.
  SshTunnelConfig? get sshTunnelConfig {
    if (driverOptions == null || driverOptions!.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(driverOptions!);
      if (decoded is Map<String, dynamic> && decoded.containsKey('ssh_tunnel')) {
        final sshMap = decoded['ssh_tunnel'];
        if (sshMap is Map<String, dynamic>) {
          return SshTunnelConfig.fromMap(sshMap);
        }
      }
    } catch (e) {
      logIgnored('local_db', e);
    }
    return null;
  }

  /// Environment tag stored in [driverOptions] (null when untagged).
  ConnectionEnvironment? get environment =>
      ConnectionEnvironment.fromDriverOptions(driverOptions);

  /// Returns a copy of this row tagged with [environment] (null removes the tag).
  ConnectionRow withEnvironment(ConnectionEnvironment? environment) {
    final options =
        ConnectionEnvironment.applyToDriverOptions(driverOptions, environment);
    return copyWith(
      driverOptions: options,
      clearDriverOptions: options == null,
    );
  }

  /// Returns a copy of this row with the given [sshTunnelConfig] encoded in [driverOptions].
  ConnectionRow withSshTunnelConfig(SshTunnelConfig? config) {
    Map<String, dynamic> opts = {};
    if (driverOptions != null && driverOptions!.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(driverOptions!);
        if (decoded is Map<String, dynamic>) {
          opts = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        logIgnored('local_db', e);
      }
    }
    if (config == null || !config.enabled) {
      opts.remove('ssh_tunnel');
    } else {
      opts['ssh_tunnel'] = config.toMap();
    }
    return copyWith(
      driverOptions: opts.isEmpty ? null : jsonEncode(opts),
      clearDriverOptions: opts.isEmpty,
    );
  }

  Map<String, Object?> toMap() => {
        'type': type,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': password,
        'database_name': databaseName,
        'auth_source': authSource,
        'use_ssl': useSSL ? 1 : 0,
        'connection_string': connectionString,
        'extension_id': extensionId,
        'driver_options': driverOptions,
        'folder_id': folderId,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };

  /// SQLite row without secrets ([password], [connectionString]); use the secure store for those.
  Map<String, Object?> toPersistenceMap() => {
        'type': type,
        'name': name,
        'host': host,
        'port': port,
        'username': username,
        'password': null,
        'database_name': databaseName,
        'auth_source': authSource,
        'use_ssl': useSSL ? 1 : 0,
        'connection_string': null,
        'extension_id': extensionId,
        'driver_options': driverOptions,
        'folder_id': folderId,
        'sort_order': sortOrder,
        'created_at': createdAt,
      };

  static ConnectionRow fromMap(Map<String, Object?> m) => ConnectionRow(
        id: sqliteInt(m['id']),
        type: m['type'] as String,
        name: m['name'] as String,
        host: m['host'] as String?,
        port: sqliteInt(m['port']),
        username: m['username'] as String?,
        password: m['password'] as String?,
        databaseName: m['database_name'] as String?,
        authSource: m['auth_source'] as String?,
        useSSL: sqliteInt(m['use_ssl']) == 1,
        connectionString: m['connection_string'] as String?,
        extensionId: m['extension_id'] as String?,
        driverOptions: m['driver_options'] as String?,
        folderId: sqliteInt(m['folder_id']),
        sortOrder: sqliteInt(m['sort_order']) ?? 0,
        createdAt: m['created_at'] as String,
      );

  ConnectionRow copyWith({
    int? id,
    String? type,
    String? name,
    String? host,
    int? port,
    String? username,
    String? password,
    String? databaseName,
    String? authSource,
    bool? useSSL,
    String? connectionString,
    String? extensionId,
    String? driverOptions,
    int? folderId,
    int? sortOrder,
    String? createdAt,
    SshTunnelSecrets? sshSecrets,
    bool? removeSavedPassword,
    bool clearPassword = false,
    bool clearConnectionString = false,
    bool clearSshSecrets = false,
    bool clearDriverOptions = false,
  }) {
    return ConnectionRow(
      id: id ?? this.id,
      type: type ?? this.type,
      name: name ?? this.name,
      host: host ?? this.host,
      port: port ?? this.port,
      username: username ?? this.username,
      password: clearPassword ? null : (password ?? this.password),
      databaseName: databaseName ?? this.databaseName,
      authSource: authSource ?? this.authSource,
      useSSL: useSSL ?? this.useSSL,
      connectionString: clearConnectionString
          ? null
          : (connectionString ?? this.connectionString),
      extensionId: extensionId ?? this.extensionId,
      driverOptions: clearDriverOptions
          ? null
          : (driverOptions ?? this.driverOptions),
      folderId: folderId ?? this.folderId,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
      sshSecrets: clearSshSecrets ? null : (sshSecrets ?? this.sshSecrets),
      removeSavedPassword: removeSavedPassword ?? this.removeSavedPassword,
    );
  }

  /// Whether in-memory password credentials are set.
  bool get hasPassword => password != null && password!.isNotEmpty;

  /// Whether in-memory connection URI credentials are set.
  bool get hasConnectionString =>
      connectionString != null && connectionString!.isNotEmpty;

  /// Whether any in-memory secret credentials are held.
  bool get hasSecrets =>
      hasPassword || hasConnectionString || (sshSecrets != null && sshSecrets!.hasAny);

  /// Returns a clean copy of this [ConnectionRow] with all secret credentials
  /// ([password], [connectionString], and [sshSecrets]) scrubbed to null.
  ConnectionRow withoutSecrets() => copyWith(
        clearPassword: true,
        clearConnectionString: true,
        clearSshSecrets: true,
      );
}
