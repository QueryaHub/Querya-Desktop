import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/mcp/mcp_redaction.dart';

/// Severity of a [QueryaLog] line.
enum QueryaLogLevel { info, warn, error }

/// The app's persistent log: timestamped lines in a file under the app data
/// root, rotated by size.
///
/// Logging never throws and never blocks the caller: lines are queued and
/// written in order, and a file that cannot be written is only reported on
/// the console. Text is passed through [McpRedaction] (URL user info,
/// `password=...`, private keys) before it is written. Callers must still not
/// pass SQL text or whole connection strings.
class QueryaLog {
  QueryaLog({this.maxBytes = 2 * 1024 * 1024, this.maxFiles = 5})
      : assert(maxFiles >= 1);

  static final QueryaLog instance = QueryaLog();

  static const fileName = 'querya.log';

  /// A file is rotated before a line would take it past this size.
  final int maxBytes;

  /// The current file plus the older ones kept (`querya.1.log`, ...).
  final int maxFiles;

  /// Lines logged before [init] (start-up) wait here, up to this many.
  static const _maxPending = 500;

  Directory? _directory;
  int _size = 0;
  Future<void> _queue = Future.value();
  final _pending = <String>[];

  /// Directory of the log files, once [init] has succeeded.
  Directory? get directory => _directory;

  /// Starts writing into [directory] and flushes what was logged before.
  /// A directory that cannot be used leaves the log console-only.
  Future<void> init(Directory directory) async {
    try {
      await directory.create(recursive: true);
      final current = File(p.join(directory.path, fileName));
      _size = await current.exists() ? await current.length() : 0;
      _directory = directory;
    } catch (e) {
      debugPrint('QueryaLog.init: $e');
      _pending.clear();
      return;
    }
    final waiting = List<String>.of(_pending);
    _pending.clear();
    waiting.forEach(_enqueue);
  }

  void info(String area, String message) =>
      write(QueryaLogLevel.info, area, message);

  void warn(String area, String message, {Object? error, StackTrace? stack}) =>
      write(QueryaLogLevel.warn, area, message, error: error, stack: stack);

  void error(String area, String message, {Object? error, StackTrace? stack}) =>
      write(QueryaLogLevel.error, area, message, error: error, stack: stack);

  /// Queues one line. Never throws.
  void write(
    QueryaLogLevel level,
    String area,
    String message, {
    Object? error,
    StackTrace? stack,
  }) {
    try {
      final text = StringBuffer(message);
      if (error != null) text.write(': $error');
      if (stack != null) text.write('\n$stack');
      final body = McpRedaction.redact(text.toString())
          .trimRight()
          .replaceAll('\n', '\n    ');
      final tag = level.name.toUpperCase().padRight(5);
      _enqueue(
        '${DateTime.now().toUtc().toIso8601String()} $tag [$area] $body\n',
      );
    } catch (e) {
      debugPrint('QueryaLog.write: $e');
    }
  }

  /// Completes when every line queued so far has been written.
  Future<void> flush() => _queue;

  /// The last [count] lines of the current and the older files, oldest first;
  /// empty when there is no log.
  Future<List<String>> tail([int count = 200]) async {
    final dir = _directory;
    if (dir == null) return const [];
    await flush();
    final lines = <String>[];
    try {
      for (var i = 0; i < maxFiles && lines.length < count; i++) {
        final file = _file(dir, i);
        if (!await file.exists()) continue;
        final fileLines = const LineSplitter().convert(await file.readAsString());
        lines.insertAll(0, fileLines);
      }
    } catch (e) {
      debugPrint('QueryaLog.tail: $e');
    }
    return lines.length > count ? lines.sublist(lines.length - count) : lines;
  }

  File _file(Directory dir, int index) => File(
        p.join(dir.path, index == 0 ? fileName : 'querya.$index.log'),
      );

  void _enqueue(String line) {
    if (_directory == null) {
      if (_pending.length < _maxPending) _pending.add(line);
      return;
    }
    _queue = _queue.then((_) => _append(line)).catchError((Object e) {
      debugPrint('QueryaLog: could not write: $e');
    });
  }

  Future<void> _append(String line) async {
    final dir = _directory!;
    final bytes = utf8.encode(line);
    if (_size > 0 && _size + bytes.length > maxBytes) {
      try {
        await _rotate(dir);
      } catch (e) {
        // A file that cannot be renamed (open in a viewer, wrong permissions)
        // must not stop the log: keep writing to the current file and try
        // again after another maxBytes.
        debugPrint('QueryaLog: could not rotate: $e');
        _size = 0;
      }
    }
    await _file(dir, 0).writeAsBytes(bytes, mode: FileMode.append);
    _size += bytes.length;
  }

  Future<void> _rotate(Directory dir) async {
    final oldest = _file(dir, maxFiles - 1);
    if (await oldest.exists()) await oldest.delete();
    for (var i = maxFiles - 2; i >= 0; i--) {
      final file = _file(dir, i);
      if (await file.exists()) await file.rename(_file(dir, i + 1).path);
    }
    _size = 0;
  }
}
