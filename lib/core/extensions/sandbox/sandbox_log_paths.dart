import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/app_data_root.dart';

/// Resolves sandbox log directories (Block E §6).
abstract final class SandboxLogPaths {
  static const sandboxSegment = 'sandbox';
  static const logsSegment = 'logs';
  static const securityAuditFileName = 'security_audit.log';

  @visibleForTesting
  static Directory? mockLogsDirectory;

  /// Portable: `{QueryaData}/logs`.
  /// Otherwise: `~/.local/share/Querya/logs` (or OS equivalents / app-support fallback).
  static Future<Directory> logsDirectory() async {
    if (mockLogsDirectory != null) return mockLogsDirectory!;

    final portable = await AppDataRoot.resolvePortableRoot();
    if (portable != null) {
      return Directory(p.join(portable.path, logsSegment));
    }

    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      if (Platform.isLinux) {
        final xdg = Platform.environment['XDG_DATA_HOME'];
        final base = (xdg != null && xdg.isNotEmpty)
            ? xdg
            : p.join(home, '.local', 'share');
        return Directory(p.join(base, 'Querya', logsSegment));
      }
      if (Platform.isMacOS) {
        return Directory(
          p.join(home, 'Library', 'Application Support', 'Querya', logsSegment),
        );
      }
      if (Platform.isWindows) {
        final appData =
            Platform.environment['APPDATA'] ?? p.join(home, 'AppData', 'Roaming');
        return Directory(p.join(appData, 'Querya', logsSegment));
      }
    }

    final support = await AppDataRoot.applicationSupportDirectory();
    return Directory(p.join(support.path, logsSegment));
  }

  static Future<Directory> ensureSandboxLogsDirectory() async {
    final dir = Directory(p.join((await logsDirectory()).path, sandboxSegment));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  static Future<File> pluginLogFile(String pluginId) async {
    final dir = await ensureSandboxLogsDirectory();
    return File(p.join(dir.path, '${_sanitizeId(pluginId)}.log'));
  }

  static Future<File> securityAuditLogFile() async {
    final root = await logsDirectory();
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return File(p.join(root.path, securityAuditFileName));
  }

  static String _sanitizeId(String pluginId) {
    final cleaned = pluginId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (cleaned.isEmpty) return 'plugin';
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }
}
