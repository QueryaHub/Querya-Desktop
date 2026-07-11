import 'dart:io';

import 'package:path/path.dart' as p;

/// Isolated read-write scratch directory for a sandboxed plugin process
/// (Block E — Filesystem Isolation).
///
/// Layout: `<base>/querya_sandbox/<pluginId>_<token>/`
/// Default base is the system temp directory (`/tmp` on Linux/macOS).
class SandboxScratchDirectory {
  SandboxScratchDirectory._(this.directory, this.pluginId);

  /// Directory name segment used under the temp base.
  static const rootSegment = 'querya_sandbox';

  final Directory directory;
  final String pluginId;

  String get path => directory.path;

  /// Creates a unique scratch directory for [pluginId].
  ///
  /// [baseDirectory] overrides the system temp root (useful in tests).
  static Future<SandboxScratchDirectory> create({
    required String pluginId,
    Directory? baseDirectory,
    String? token,
  }) async {
    final sanitized = _sanitizePluginId(pluginId);
    final unique = token ??
        '${DateTime.now().microsecondsSinceEpoch}_$pid';
    final base = baseDirectory ?? Directory.systemTemp;
    final dir = Directory(
      p.join(base.path, rootSegment, '${sanitized}_$unique'),
    );
    await dir.create(recursive: true);
    return SandboxScratchDirectory._(dir, pluginId);
  }

  /// Deletes the scratch directory and all contents. Safe if already gone.
  Future<void> delete() async {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    } on PathNotFoundException {
      // Already removed.
    } on FileSystemException {
      // Best-effort cleanup; process may still hold a handle briefly.
      try {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      } catch (_) {
        // Ignore secondary failure — caller already tore down the process.
      }
    }
  }

  /// Removes orphaned scratch trees older than [maxAge] under [baseDirectory].
  static Future<int> cleanupOrphans({
    Directory? baseDirectory,
    Duration maxAge = const Duration(hours: 24),
  }) async {
    final root = Directory(
      p.join((baseDirectory ?? Directory.systemTemp).path, rootSegment),
    );
    if (!await root.exists()) return 0;

    final cutoff = DateTime.now().subtract(maxAge);
    var removed = 0;
    await for (final entity in root.list()) {
      if (entity is! Directory) continue;
      try {
        final stat = await entity.stat();
        if (stat.modified.isBefore(cutoff)) {
          await entity.delete(recursive: true);
          removed++;
        }
      } catch (_) {
        // Skip entries we cannot inspect or delete.
      }
    }
    return removed;
  }

  static String _sanitizePluginId(String pluginId) {
    final cleaned = pluginId.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
    if (cleaned.isEmpty) return 'plugin';
    return cleaned.length > 64 ? cleaned.substring(0, 64) : cleaned;
  }
}
