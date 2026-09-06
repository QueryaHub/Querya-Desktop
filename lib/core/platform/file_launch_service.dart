import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/storage/local_db.dart';

/// Supported file types for desktop "Open With" and CLI file launch.
enum FileLaunchKind {
  sql,
  sqlite,
  unknown,
}

/// Represents a validated file targeted for launch.
class FileLaunchTarget {
  const FileLaunchTarget({
    required this.path,
    required this.kind,
  });

  final String path;
  final FileLaunchKind kind;

  String get fileName => p.basename(path);
  String get nameWithoutExtension => p.basenameWithoutExtension(path);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileLaunchTarget &&
          runtimeType == other.runtimeType &&
          path == other.path &&
          kind == other.kind;

  @override
  int get hashCode => Object.hash(path, kind);

  @override
  String toString() => 'FileLaunchTarget(path: $path, kind: $kind)';
}

/// Coordinates desktop file associations, CLI file arguments, and automatic workspace loading.
class FileLaunchService {
  FileLaunchService._();

  static final FileLaunchService instance = FileLaunchService._();

  final List<FileLaunchTarget> _pendingTargets = [];

  List<FileLaunchTarget> get pendingTargets => List.unmodifiable(_pendingTargets);

  bool get hasPendingTargets => _pendingTargets.isNotEmpty;

  /// Returns the first pending launch target, or `null` if none.
  FileLaunchTarget? get pendingTarget =>
      _pendingTargets.isNotEmpty ? _pendingTargets.first : null;

  /// Whether there is at least one pending launch target.
  bool get hasPendingTarget => _pendingTargets.isNotEmpty;

  /// Sets or clears the pending launch target (useful for testing or single-target flows).
  void setPendingTarget(FileLaunchTarget? target) {
    _pendingTargets.clear();
    if (target != null) {
      _pendingTargets.add(target);
    }
  }

  /// Detects the [FileLaunchKind] based on the file extension.
  static FileLaunchKind detectKind(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.sql':
        return FileLaunchKind.sql;
      case '.sqlite':
      case '.sqlite3':
      case '.db':
      case '.db3':
        return FileLaunchKind.sqlite;
      default:
        return FileLaunchKind.unknown;
    }
  }

  /// Parses a single command-line argument or URL string into a [FileLaunchTarget].
  ///
  /// Supports raw file paths, file:// URIs, and strips surrounding quotes.
  static FileLaunchTarget? parseArgument(String rawArg) {
    var cleaned = rawArg.trim();
    if (cleaned.isEmpty) return null;

    // Ignore command-line flags
    if (cleaned.startsWith('-')) return null;

    // Strip surrounding quotes if present
    if ((cleaned.startsWith('"') && cleaned.endsWith('"')) ||
        (cleaned.startsWith("'") && cleaned.endsWith("'"))) {
      cleaned = cleaned.substring(1, cleaned.length - 1).trim();
    }

    // Convert file:// URIs
    if (cleaned.startsWith('file://')) {
      try {
        final uri = Uri.parse(cleaned);
        cleaned = uri.toFilePath();
      } catch (_) {
        return null;
      }
    }

    final normalized = p.normalize(p.absolute(cleaned));
    final kind = detectKind(normalized);
    if (kind == FileLaunchKind.unknown) return null;

    return FileLaunchTarget(path: normalized, kind: kind);
  }

  /// Processes entrypoint command-line arguments and adds to [pendingTargets] if matching files are found.
  void processLaunchArguments(List<String> args) {
    for (final arg in args) {
      final target = parseArgument(arg);
      if (target != null) {
        _pendingTargets.add(target);
      }
    }
  }

  /// Adds a target to the pending launch list (e.g. for testing or runtime open events).
  void addPendingTarget(FileLaunchTarget target) {
    _pendingTargets.add(target);
  }

  /// Consumes and returns the first pending launch target, or `null` if none.
  FileLaunchTarget? consumePendingTarget() {
    if (_pendingTargets.isEmpty) return null;
    return _pendingTargets.removeAt(0);
  }

  /// Returns and clears all current [pendingTargets].
  List<FileLaunchTarget> consumePendingTargets() {
    final targets = List<FileLaunchTarget>.from(_pendingTargets);
    _pendingTargets.clear();
    return targets;
  }

  /// Resolves or registers a SQLite database [ConnectionRow] for [target].
  ///
  /// If a connection for [target.path] already exists in [LocalDb], returns it.
  /// Otherwise, persists a new SQLite connection and returns the saved row.
  Future<ConnectionRow> resolveOrRegisterSqliteConnection(
    FileLaunchTarget target,
  ) async {
    final connections = await LocalDb.instance.getConnections();
    for (final conn in connections) {
      if (conn.type == 'sqlite' && conn.host != null) {
        final existingNormalized = p.normalize(p.absolute(conn.host!));
        if (existingNormalized == target.path) {
          return conn;
        }
      }
    }

    final displayName = target.nameWithoutExtension.isNotEmpty
        ? target.nameWithoutExtension
        : target.fileName;

    final newRow = ConnectionRow(
      name: displayName,
      type: 'sqlite',
      host: target.path,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    final id = await LocalDb.instance.addConnection(newRow);
    return newRow.copyWith(id: id);
  }

  /// Reads the full text of an SQL script for [target].
  Future<String> readSqlContent(FileLaunchTarget target) async {
    final file = File(target.path);
    if (!await file.exists()) {
      throw FileSystemException('SQL file not found', target.path);
    }
    return file.readAsString();
  }
}
