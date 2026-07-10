/// Sandbox declaration parsed from the `sandbox` block of an extension
/// manifest (Block E — Sandbox Runtime).
///
/// Example manifest fragment:
/// ```json
/// "sandbox": {
///   "engine": "process",
///   "permissions": {
///     "network": { "mode": "connection_host_only", "allow_ssl": true },
///     "filesystem": { "scratch_mb": 100, "access": "scratch_only" },
///     "resources": { "memory_mb": 256, "max_open_files": 64 }
///   }
/// }
/// ```
library;

/// Execution engine requested by the extension.
enum SandboxEngine {
  /// Level 2 — managed OS process (bwrap / sandbox-exec / AppContainer).
  process('process'),

  /// Level 1 — embedded WASM runtime inside the host process.
  wasm('wasm'),

  /// Level 1 — embedded QuickJS runtime inside the host process.
  quickjs('quickjs'),

  unknown('unknown');

  const SandboxEngine(this.value);
  final String value;

  static SandboxEngine fromString(String? value) {
    if (value == null) return SandboxEngine.unknown;
    return SandboxEngine.values.firstWhere(
      (e) => e.value == value,
      orElse: () => SandboxEngine.unknown,
    );
  }

  /// Embedded engines run in-process with full memory isolation.
  bool get isEmbedded => this == SandboxEngine.wasm || this == SandboxEngine.quickjs;
}

/// Network access mode requested by the extension.
enum NetworkPermissionMode {
  /// No sockets at all (themes, parsers, SDUI transformers).
  none('none'),

  /// Outgoing TCP/TLS only to the user-configured `connection.host:port`.
  connectionHostOnly('connection_host_only'),

  unknown('unknown');

  const NetworkPermissionMode(this.value);
  final String value;

  static NetworkPermissionMode fromString(String? value) {
    if (value == null) return NetworkPermissionMode.none;
    return NetworkPermissionMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => NetworkPermissionMode.unknown,
    );
  }
}

class NetworkPermission {
  const NetworkPermission({
    this.mode = NetworkPermissionMode.none,
    this.allowSsl = false,
  });

  final NetworkPermissionMode mode;
  final bool allowSsl;

  factory NetworkPermission.fromJson(Map<String, dynamic> json) {
    return NetworkPermission(
      mode: NetworkPermissionMode.fromString(json['mode'] as String?),
      allowSsl: json['allow_ssl'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'mode': mode.value,
        'allow_ssl': allowSsl,
      };
}

class FilesystemPermission {
  const FilesystemPermission({
    this.scratchMb = defaultScratchMb,
    this.access = scratchOnlyAccess,
  });

  static const scratchOnlyAccess = 'scratch_only';
  static const defaultScratchMb = 100;

  /// Quota for the read-write scratch directory, in megabytes.
  final int scratchMb;

  /// Filesystem access scope. Only [scratchOnlyAccess] is supported.
  final String access;

  factory FilesystemPermission.fromJson(Map<String, dynamic> json) {
    return FilesystemPermission(
      scratchMb: json['scratch_mb'] as int? ?? defaultScratchMb,
      access: json['access'] as String? ?? scratchOnlyAccess,
    );
  }

  Map<String, dynamic> toJson() => {
        'scratch_mb': scratchMb,
        'access': access,
      };
}

class ResourceLimits {
  const ResourceLimits({
    this.memoryMb = defaultMemoryMb,
    this.maxOpenFiles = defaultMaxOpenFiles,
  });

  static const defaultMemoryMb = 256;
  static const defaultMaxOpenFiles = 64;

  /// Hard RAM limit for the plugin process, in megabytes.
  final int memoryMb;

  /// Maximum number of open file descriptors (`ulimit -n`).
  final int maxOpenFiles;

  factory ResourceLimits.fromJson(Map<String, dynamic> json) {
    return ResourceLimits(
      memoryMb: json['memory_mb'] as int? ?? defaultMemoryMb,
      maxOpenFiles: json['max_open_files'] as int? ?? defaultMaxOpenFiles,
    );
  }

  Map<String, dynamic> toJson() => {
        'memory_mb': memoryMb,
        'max_open_files': maxOpenFiles,
      };
}

/// Full sandbox requirements block declared by an extension.
class SandboxCapabilities {
  const SandboxCapabilities({
    required this.engine,
    this.network = const NetworkPermission(),
    this.filesystem = const FilesystemPermission(),
    this.resources = const ResourceLimits(),
  });

  final SandboxEngine engine;
  final NetworkPermission network;
  final FilesystemPermission filesystem;
  final ResourceLimits resources;

  factory SandboxCapabilities.fromJson(Map<String, dynamic> json) {
    final permissions = json['permissions'] as Map<String, dynamic>? ?? const {};
    return SandboxCapabilities(
      engine: SandboxEngine.fromString(json['engine'] as String?),
      network: permissions['network'] is Map<String, dynamic>
          ? NetworkPermission.fromJson(permissions['network'] as Map<String, dynamic>)
          : const NetworkPermission(),
      filesystem: permissions['filesystem'] is Map<String, dynamic>
          ? FilesystemPermission.fromJson(permissions['filesystem'] as Map<String, dynamic>)
          : const FilesystemPermission(),
      resources: permissions['resources'] is Map<String, dynamic>
          ? ResourceLimits.fromJson(permissions['resources'] as Map<String, dynamic>)
          : const ResourceLimits(),
    );
  }

  Map<String, dynamic> toJson() => {
        'engine': engine.value,
        'permissions': {
          'network': network.toJson(),
          'filesystem': filesystem.toJson(),
          'resources': resources.toJson(),
        },
      };
}
