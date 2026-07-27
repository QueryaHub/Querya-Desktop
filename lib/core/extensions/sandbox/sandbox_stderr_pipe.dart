import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_rotating_log.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_sanitizer.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_security_audit.dart';

/// Captures `process.stderr`, sanitizes it, and writes to a rotating log.
///
/// Incomplete lines are held in a capped carry buffer. Newline scanning walks
/// only the new chunk (no full-buffer `split` rebuild each time). Oversized
/// lines are truncated and the remainder is dropped until the next newline.
class SandboxStderrPipe {
  SandboxStderrPipe({
    required this.pluginId,
    required this.log,
    this.audit,
    this.onSanitizedLine,
    this.maxCarryChars = defaultMaxCarryChars,
    this.maxSanitizeChars = defaultMaxSanitizeChars,
  }) : assert(maxCarryChars > 0),
       assert(maxSanitizeChars > 0);

  /// Default cap for an incomplete stderr line held across chunks.
  static const defaultMaxCarryChars = 256 * 1024;

  /// Default max length passed into [SandboxSanitizer.sanitize].
  static const defaultMaxSanitizeChars = 256 * 1024;

  static const _truncatedSuffix = '…[truncated]';

  final String pluginId;
  final SandboxRotatingLog log;
  final SandboxSecurityAudit? audit;
  final void Function(String line)? onSanitizedLine;
  final int maxCarryChars;
  final int maxSanitizeChars;

  StreamSubscription<List<int>>? _subscription;
  final StringBuffer _carry = StringBuffer();
  int _carryLength = 0;
  var _dropUntilNewline = false;
  Future<void> _writeChain = Future<void>.value();
  var _closed = false;

  bool get isAttached => _subscription != null && !_closed;

  /// Creates a pipe for [handle] writing to the standard sandbox log path.
  static Future<SandboxStderrPipe> attach(
    SandboxProcessHandle handle, {
    SandboxSecurityAudit? audit,
    int maxBytes = 5 * 1024 * 1024,
    int maxFiles = 2,
    int maxCarryChars = defaultMaxCarryChars,
    int maxSanitizeChars = defaultMaxSanitizeChars,
    void Function(String line)? onSanitizedLine,
  }) async {
    final file = await SandboxLogPaths.pluginLogFile(handle.pluginId);
    final pipe = SandboxStderrPipe(
      pluginId: handle.pluginId,
      log: SandboxRotatingLog(
        file: file,
        maxBytes: maxBytes,
        maxFiles: maxFiles,
      ),
      audit: audit,
      onSanitizedLine: onSanitizedLine,
      maxCarryChars: maxCarryChars,
      maxSanitizeChars: maxSanitizeChars,
    );
    pipe.listen(handle.process.stderr);
    return pipe;
  }

  /// Starts consuming [stderr]. Safe to call once.
  void listen(Stream<List<int>> stderr) {
    if (_subscription != null) {
      throw StateError('SandboxStderrPipe already attached');
    }
    _subscription = stderr.listen(
      _onBytes,
      onError: (Object e, StackTrace st) {
        debugPrint('SandboxStderrPipe($pluginId) stderr error: $e');
      },
      onDone: () {
        _writeChain = _writeChain.then((_) => _flushCarry());
      },
      cancelOnError: false,
    );
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _writeChain;
    await _flushCarry();
  }

  void _onBytes(List<int> chunk) {
    if (chunk.isEmpty) return;
    var text = utf8.decode(chunk, allowMalformed: true);
    if (_dropUntilNewline) {
      final nl = text.indexOf('\n');
      if (nl < 0) return;
      _dropUntilNewline = false;
      text = text.substring(nl + 1);
      if (text.isEmpty) return;
    }
    _drainIncoming(text);
  }

  /// Scan [incoming] for newlines; only the incomplete tail stays in [_carry].
  void _drainIncoming(String incoming) {
    var start = 0;
    while (true) {
      final nl = incoming.indexOf('\n', start);
      if (nl < 0) {
        _appendCarry(incoming.substring(start));
        return;
      }
      final segment = incoming.substring(start, nl);
      final line = _carryLength == 0
          ? segment
          : (_carry..write(segment)).toString();
      if (_carryLength != 0) {
        _carry.clear();
        _carryLength = 0;
      }
      _enqueueLine(line);
      start = nl + 1;
    }
  }

  void _appendCarry(String rest) {
    if (rest.isEmpty) return;
    if (_carryLength + rest.length <= maxCarryChars) {
      _carry.write(rest);
      _carryLength += rest.length;
      return;
    }

    final room = maxCarryChars - _carryLength;
    if (room > 0) {
      _carry.write(rest.substring(0, room));
      _carryLength += room;
    }
    final flushed = '${_carry.toString()}$_truncatedSuffix';
    _carry.clear();
    _carryLength = 0;
    _dropUntilNewline = true;
    _enqueueLine(flushed);

    if (room < rest.length) {
      final nl = rest.indexOf('\n', room);
      if (nl >= 0) {
        _dropUntilNewline = false;
        final after = rest.substring(nl + 1);
        if (after.isNotEmpty) {
          _drainIncoming(after);
        }
      }
    }
  }

  void _enqueueLine(String raw) {
    _writeChain = _writeChain.then((_) => _writeSanitized(raw));
  }

  Future<void> _flushCarry() async {
    if (_carryLength == 0) return;
    final raw = _carry.toString();
    _carry.clear();
    _carryLength = 0;
    await _writeSanitized(raw);
  }

  Future<void> _writeSanitized(String raw) async {
    try {
      final bounded = raw.length > maxSanitizeChars
          ? raw.substring(0, maxSanitizeChars)
          : raw;
      final sanitized = SandboxSanitizer.sanitize(bounded);
      if (sanitized != bounded && audit != null) {
        await audit!.record(
          type: SandboxSecurityEventType.secretLeakBlocked,
          pluginId: pluginId,
          detail: 'stderr redaction applied',
        );
      }
      onSanitizedLine?.call(sanitized);
      await log.appendLine(sanitized);
    } catch (e, st) {
      debugPrint('SandboxStderrPipe($pluginId) write failed: $e\n$st');
    }
  }
}
