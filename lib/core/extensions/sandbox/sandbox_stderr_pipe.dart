import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_log_paths.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_rotating_log.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_sanitizer.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_security_audit.dart';

/// Captures `process.stderr`, sanitizes it, and writes to a rotating log.
class SandboxStderrPipe {
  SandboxStderrPipe({
    required this.pluginId,
    required this.log,
    this.audit,
    this.onSanitizedLine,
  });

  final String pluginId;
  final SandboxRotatingLog log;
  final SandboxSecurityAudit? audit;
  final void Function(String line)? onSanitizedLine;

  StreamSubscription<List<int>>? _subscription;
  final StringBuffer _carry = StringBuffer();
  Future<void> _writeChain = Future<void>.value();
  var _closed = false;

  bool get isAttached => _subscription != null && !_closed;

  /// Creates a pipe for [handle] writing to the standard sandbox log path.
  static Future<SandboxStderrPipe> attach(
    SandboxProcessHandle handle, {
    SandboxSecurityAudit? audit,
    int maxBytes = 5 * 1024 * 1024,
    int maxFiles = 2,
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
    _carry.write(utf8.decode(chunk, allowMalformed: true));
    _drainLines();
  }

  void _drainLines() {
    final text = _carry.toString();
    final parts = text.split('\n');
    _carry.clear();
    if (!text.endsWith('\n')) {
      _carry.write(parts.removeLast());
    } else if (parts.isNotEmpty && parts.last.isEmpty) {
      parts.removeLast();
    }

    for (final raw in parts) {
      _writeChain = _writeChain.then((_) => _writeSanitized(raw));
    }
  }

  Future<void> _flushCarry() async {
    if (_carry.isEmpty) return;
    final raw = _carry.toString();
    _carry.clear();
    await _writeSanitized(raw);
  }

  Future<void> _writeSanitized(String raw) async {
    try {
      final sanitized = SandboxSanitizer.sanitize(raw);
      if (sanitized != raw && audit != null) {
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
