import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/rpc/json_rpc_stdio_client.dart';
import 'package:querya_desktop/core/extensions/rpc/plugin_rpc_exceptions.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_process_runner.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_security_audit.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_stderr_pipe.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_watchdog.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_auto_recovery.dart';

/// High-level JSON-RPC bridge to a sandboxed plugin process (Block C).
///
/// Owns process lifetime ([SandboxProcessRunner]), Stdio JSON-RPC,
/// optional stderr sanitization, and heartbeat watchdog.
class PluginRpcBridge {
  PluginRpcBridge({
    SandboxProcessRunner? processRunner,
    this.handshakeTimeout = const Duration(seconds: 3),
    this.shutdownTimeout = const Duration(seconds: 3),
    this.requestTimeout = const Duration(seconds: 30),
    this.enableWatchdog = true,
    this.enableStderrPipe = true,
    SandboxSecurityAudit? audit,
    SandboxAutoRecovery? recovery,
  })  : _runner = processRunner ?? SandboxProcessRunner(),
        _audit = audit,
        _recovery = recovery ?? SandboxAutoRecovery();

  final SandboxProcessRunner _runner;
  final Duration handshakeTimeout;
  final Duration shutdownTimeout;
  final Duration requestTimeout;
  final bool enableWatchdog;
  final bool enableStderrPipe;
  final SandboxSecurityAudit? _audit;
  final SandboxAutoRecovery _recovery;

  SandboxProcessHandle? _handle;
  JsonRpcStdioClient? _client;
  SandboxStderrPipe? _stderrPipe;
  SandboxWatchdog? _watchdog;
  StreamSubscription<int>? _exitSub;
  var _started = false;
  var _shuttingDown = false;

  bool get isStarted => _started && _handle != null && !(_handle!.isDisposed);

  String? get pluginId => _handle?.pluginId;

  SandboxProcessHandle? get handle => _handle;

  SandboxAutoRecovery get recovery => _recovery;

  /// Spawns the plugin, attaches RPC + optional pipes, and runs handshake.
  Future<Object?> start({
    required ExtensionManifest manifest,
    required String pluginExecutable,
    List<String> pluginArguments = const [],
    String? extensionRoot,
    Map<String, String>? environment,
    Map<String, Object?>? handshakeParams,
    bool allowUnsandboxedLaunch = false,
  }) async {
    if (_started) {
      throw StateError('PluginRpcBridge already started');
    }

    final capabilities = manifest.sandbox ??
        const SandboxCapabilities(engine: SandboxEngine.process);

    final handle = await _runner.start(
      pluginId: manifest.id,
      pluginExecutable: pluginExecutable,
      pluginArguments: pluginArguments,
      extensionRoot: extensionRoot ?? manifest.installPath,
      capabilities: capabilities,
      environment: environment,
      allowUnsandboxedLaunch: allowUnsandboxedLaunch,
    );

    _handle = handle;
    _started = true;

    final client = JsonRpcStdioClient(
      stdout: handle.process.stdout,
      stdin: handle.process.stdin,
      requestTimeout: requestTimeout,
    );
    _client = client;

    _exitSub = handle.process.exitCode.asStream().listen((code) {
      if (!_started || _shuttingDown) return;
      _onProcessExited(code);
    }, onError: (Object e, StackTrace st) {
      if (!_started || _shuttingDown) return;
      debugPrint('PluginRpcBridge exit watch error: $e\n$st');
      _failPending(PluginCrashedException(
        pluginId: handle.pluginId,
        message: '$e',
      ));
    });

    if (enableStderrPipe) {
      try {
        _stderrPipe = await SandboxStderrPipe.attach(
          handle,
          audit: _audit,
        );
      } catch (e) {
        debugPrint('PluginRpcBridge: stderr pipe attach failed: $e');
      }
    }

    if (enableWatchdog) {
      _watchdog = SandboxWatchdog(
        recovery: _recovery,
        onStopped: (reason) {
          if (reason == SandboxWatchdogStopReason.deadlock) {
            unawaited(_audit?.record(
              type: SandboxSecurityEventType.deadlock,
              pluginId: handle.pluginId,
              detail: 'watchdog deadlock',
            ));
          }
        },
      );
      _watchdog!.start(handle, client: client);
    }

    try {
      final result = await client
          .sendRequest('system.handshake', handshakeParams ?? const {})
          .timeout(handshakeTimeout);
      _recovery.recordSuccess();
      return result;
    } on TimeoutException {
      await _forceKill();
      throw PluginProtocolTimeoutException(
        'system.handshake timed out after $handshakeTimeout',
      );
    }
  }

  /// Sends a JSON-RPC request to the plugin.
  Future<Object?> sendRequest(String method, [Object? params]) {
    final client = _client;
    if (client == null || !isStarted) {
      throw StateError('PluginRpcBridge is not started');
    }
    return client.sendRequest(method, params);
  }

  Future<Object?> ping() => sendRequest('system.ping');

  Future<Object?> injectCredentials(Map<String, Object?> params) =>
      sendRequest('system.injectCredentials', params);

  Future<Object?> connect(Map<String, Object?> params) =>
      sendRequest('db.connect', params);

  /// Asks the plugin to shut down, then disposes the process and scratch dir.
  Future<void> shutdown() async {
    if (!_started && _handle == null) return;
    _shuttingDown = true;
    final client = _client;
    final handle = _handle;

    _watchdog?.stop();
    _watchdog = null;

    if (client != null && handle != null && !handle.isDisposed) {
      try {
        await client
            .sendRequest('system.shutdown')
            .timeout(shutdownTimeout);
      } catch (e) {
        debugPrint('PluginRpcBridge.shutdown RPC: $e');
      }

      try {
        await handle.process.exitCode.timeout(shutdownTimeout);
      } on TimeoutException {
        await handle.kill();
      } catch (_) {
        await handle.kill();
      }
    }

    await _disposeLocal();
    _shuttingDown = false;
  }

  Future<void> _forceKill() async {
    final handle = _handle;
    if (handle != null && !handle.isDisposed) {
      await handle.kill();
    }
    await _disposeLocal();
  }

  void _onProcessExited(int code) {
    if (!_started) return;
    debugPrint('PluginRpcBridge: process exited with $code');
    if (code != 0) {
      _recovery.recordFailure();
    }
    _failPending(PluginCrashedException(
      pluginId: _handle?.pluginId ?? 'unknown',
      exitCode: code,
    ));
    unawaited(_disposeLocal(keepRecovery: true));
  }

  void _failPending(Object error) {
    _client?.failAll(error);
    unawaited(_client?.close());
    if (error is PluginCrashedException) {
      debugPrint('$error');
    }
  }

  Future<void> _disposeLocal({bool keepRecovery = false}) async {
    _started = false;
    await _exitSub?.cancel();
    _exitSub = null;
    _watchdog?.stop();
    _watchdog = null;
    await _stderrPipe?.close();
    _stderrPipe = null;
    await _client?.close();
    _client = null;
    final handle = _handle;
    _handle = null;
    if (handle != null && !handle.isDisposed) {
      await handle.dispose();
    }
    if (!keepRecovery) {
      // leave recovery state as-is for auto-restart decisions
    }
  }
}
