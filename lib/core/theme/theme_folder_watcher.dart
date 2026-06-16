import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Watches the user themes directory and notifies when registry files change.
class ThemeFolderWatcher {
  ThemeFolderWatcher({
    required Future<Directory> Function() themesDirectory,
    required Future<void> Function() onThemesChanged,
    this.debounce = const Duration(milliseconds: 400),
  })  : _themesDirectory = themesDirectory,
        _onThemesChanged = onThemesChanged;

  final Future<Directory> Function() _themesDirectory;
  final Future<void> Function() _onThemesChanged;
  final Duration debounce;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  bool _started = false;
  bool _refreshInFlight = false;

  bool get isStarted => _started;

  /// Starts watching if not already active. No-op when the directory is missing
  /// and cannot be created.
  Future<void> start() async {
    if (_started) return;

    final directory = await _themesDirectory();
    if (!await directory.exists()) {
      try {
        await directory.create(recursive: true);
      } on Object catch (error) {
        debugPrint(
            'ThemeFolderWatcher: cannot create themes directory ($error)');
        return;
      }
    }

    try {
      _subscription = directory.watch(recursive: true).listen(
        _onFilesystemEvent,
        onError: (Object error) {
          debugPrint('ThemeFolderWatcher: watch error ($error)');
        },
      );
      _started = true;
    } on Object catch (error) {
      debugPrint('ThemeFolderWatcher: watch unavailable ($error)');
    }
  }

  /// Cancels the watcher and pending debounced refresh.
  Future<void> stop() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _started = false;
    _refreshInFlight = false;
  }

  void _onFilesystemEvent(FileSystemEvent event) {
    if (!_isRelevantEvent(event)) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      unawaited(_triggerRefresh());
    });
  }

  Future<void> _triggerRefresh() async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      await _onThemesChanged();
    } on Object catch (error) {
      debugPrint('ThemeFolderWatcher: refresh failed ($error)');
    } finally {
      _refreshInFlight = false;
    }
  }

  bool _isRelevantEvent(FileSystemEvent event) {
    final path = event.path;
    if (path.isEmpty) return false;

    final baseName = p.basename(path);
    if (baseName.startsWith('.')) return false;
    if (baseName.endsWith('.tmp') || baseName.endsWith('~')) return false;

    if (_looksLikeThemePath(path)) return true;

    if (event.type == FileSystemEvent.create ||
        event.type == FileSystemEvent.delete ||
        event.type == FileSystemEvent.move) {
      return p.extension(path).isEmpty;
    }
    return false;
  }

  bool _looksLikeThemePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.json') || lower.endsWith('.jsonc');
  }
}
