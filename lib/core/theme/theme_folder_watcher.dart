import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Watches the user themes directory and notifies when registry files change.
class ThemeFolderWatcher {
  ThemeFolderWatcher({
    required Future<Directory> Function() themesDirectory,
    required Future<void> Function({required bool structuralChange})
        onThemesChanged,
    this.debounce = const Duration(milliseconds: 400),
  })  : _themesDirectory = themesDirectory,
        _onThemesChanged = onThemesChanged;

  final Future<Directory> Function() _themesDirectory;
  final Future<void> Function({required bool structuralChange})
      _onThemesChanged;
  final Duration debounce;

  StreamSubscription<FileSystemEvent>? _subscription;
  Timer? _debounceTimer;
  bool _started = false;
  bool _refreshInFlight = false;
  bool _pendingStructural = false;

  bool get isStarted => _started;

  /// Starts watching if not already active. No-op when the directory is missing
  /// and cannot be created.
  Future<void> start() async {
    if (_started) return;
    _started = true; // Set synchronously to prevent concurrent leaks

    final directory = await _themesDirectory();
    if (!await directory.exists()) {
      try {
        await directory.create(recursive: true);
      } on Object catch (error) {
        _started = false;
        debugPrint(
            'ThemeFolderWatcher: cannot create themes directory ($error)');
        return;
      }
    }

    try {
      runZonedGuarded(() {
        final stream = directory.watch(recursive: true);
        _subscription = stream.listen(
          _onFilesystemEvent,
          onError: (Object error) {
            _started = false;
            debugPrint('ThemeFolderWatcher: watch error ($error)');
          },
          cancelOnError: false,
        );
      }, (error, stack) {
        _started = false;
        debugPrint('ThemeFolderWatcher: watch unavailable zone ($error)');
      });
    } on Object catch (error) {
      _started = false;
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
    _pendingStructural = false;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }

  void _onFilesystemEvent(FileSystemEvent event) {
    if (!_isRelevantEvent(event)) return;

    if (event is FileSystemCreateEvent ||
        event is FileSystemDeleteEvent ||
        event is FileSystemMoveEvent) {
      _pendingStructural = true;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () {
      final structural = _pendingStructural;
      _pendingStructural = false;
      unawaited(_triggerRefresh(structuralChange: structural));
    });
  }

  Future<void> _triggerRefresh({required bool structuralChange}) async {
    if (_refreshInFlight) return;
    _refreshInFlight = true;
    try {
      await _onThemesChanged(structuralChange: structuralChange);
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
