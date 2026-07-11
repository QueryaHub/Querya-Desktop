import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_auto_recovery.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';

/// Why the watchdog stopped monitoring a plugin process.
enum SandboxWatchdogStopReason {
  /// [SandboxWatchdog.stop] was called explicitly.
  stopped,

  /// Plugin failed to answer `system.ping` within the pong timeout.
  deadlock,

  /// Child process exited on its own.
  processExited,
}

/// Heartbeat monitor for a sandboxed plugin process (Block E §4).
///
/// Sends `system.ping` every [pingInterval]. If no successful response arrives
/// within [pongTimeout], marks a deadlock, SIGKILLs the process, and records
/// the failure on [recovery].
class SandboxWatchdog {
  SandboxWatchdog({
    this.pingInterval = const Duration(seconds: 30),
    this.pongTimeout = const Duration(seconds: 5),
    this.recovery,
    Future<Object?> Function()? ping,
    void Function(SandboxWatchdogStopReason reason)? onStopped,
  })  : _pingOverride = ping,
        _onStopped = onStopped;

  final Duration pingInterval;
  final Duration pongTimeout;
  final SandboxAutoRecovery? recovery;
  final Future<Object?> Function()? _pingOverride;
  final void Function(SandboxWatchdogStopReason reason)? _onStopped;

  SandboxProcessHandle? _handle;
  JsonRpcStdioClient? _client;
  Timer? _timer;
  var _running = false;
  var _pingInFlight = false;
  var _ownsClient = false;
  SandboxWatchdogStopReason? _lastReason;
  StreamSubscription<int>? _exitSub;

  bool get isRunning => _running;

  SandboxWatchdogStopReason? get lastStopReason => _lastReason;

  /// Starts monitoring [handle]. Cancels any previous session first.
  void start(SandboxProcessHandle handle, {JsonRpcStdioClient? client}) {
    stop(reason: SandboxWatchdogStopReason.stopped, notify: false);
    _handle = handle;
    _client = client;
    _ownsClient = client == null;
    _running = true;
    _lastReason = null;

    _exitSub = handle.process.exitCode.asStream().listen((code) {
      if (!_running) return;
      debugPrint(
        'SandboxWatchdog: ${handle.pluginId} exited with code $code',
      );
      recovery?.recordFailure();
      _finish(SandboxWatchdogStopReason.processExited);
    }, onError: (_) {
      if (!_running) return;
      recovery?.recordFailure();
      _finish(SandboxWatchdogStopReason.processExited);
    });

    _timer = Timer.periodic(pingInterval, (_) {
      unawaited(_tick());
    });
  }

  /// Stops timers and releases the RPC client. Does not kill the process
  /// unless [reason] is [SandboxWatchdogStopReason.deadlock] (already killed).
  void stop({
    SandboxWatchdogStopReason reason = SandboxWatchdogStopReason.stopped,
    bool notify = true,
  }) {
    if (!_running && _timer == null && _client == null && _exitSub == null) {
      return;
    }
    _running = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_exitSub?.cancel());
    _exitSub = null;
    final client = _client;
    final ownsClient = _ownsClient;
    _client = null;
    if (client != null && ownsClient) {
      unawaited(client.close());
    }
    _handle = null;
    _lastReason = reason;
    if (notify) {
      _onStopped?.call(reason);
    }
  }

  Future<void> _tick() async {
    if (!_running || _pingInFlight) return;
    _pingInFlight = true;
    try {
      final result = await _sendPing().timeout(pongTimeout);
      if (!_running) return;
      if (!isPong(result)) {
        await _onDeadlock('unexpected ping result: $result');
        return;
      }
      recovery?.recordSuccess();
    } on TimeoutException {
      if (!_running) return;
      await _onDeadlock('system.ping timed out after $pongTimeout');
    } catch (e) {
      if (!_running) return;
      await _onDeadlock('system.ping failed: $e');
    } finally {
      _pingInFlight = false;
    }
  }

  Future<Object?> _sendPing() {
    final override = _pingOverride;
    if (override != null) return override();

    final handle = _handle;
    if (handle == null) {
      throw StateError('SandboxWatchdog has no handle');
    }
    if (_client == null) {
      _client = JsonRpcStdioClient(
        stdout: handle.process.stdout,
        stdin: handle.process.stdin,
        requestTimeout: pongTimeout,
      );
      _ownsClient = true;
    }
    return _client!.sendRequest('system.ping');
  }

  Future<void> _onDeadlock(String detail) async {
    final handle = _handle;
    debugPrint(
      'SandboxWatchdog: deadlock on ${handle?.pluginId ?? 'unknown'} — $detail',
    );
    recovery?.recordFailure();
    // Cancel exit watcher before kill so we don't double-count the failure.
    await _exitSub?.cancel();
    _exitSub = null;
    if (handle != null && !handle.isDisposed) {
      await handle.kill();
    }
    _finish(SandboxWatchdogStopReason.deadlock);
  }

  void _finish(SandboxWatchdogStopReason reason) {
    stop(reason: reason);
  }

  /// Accepts common pong shapes from plugin runtimes.
  static bool isPong(Object? result) {
    if (result == null) return true;
    if (result == true) return true;
    if (result == 'pong') return true;
    if (result is Map &&
        (result['pong'] == true || result['result'] == 'pong')) {
      return true;
    }
    // Any non-error JSON-RPC result counts as alive.
    return true;
  }
}
