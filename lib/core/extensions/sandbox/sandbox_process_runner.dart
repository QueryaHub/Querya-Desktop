import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_os_isolation.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_secret_guard.dart';

/// Live handle for a sandboxed OS process (Block E Level 2).
class SandboxProcessHandle {
  SandboxProcessHandle({
    required this.pluginId,
    required this.process,
    required this.scratch,
    required this.launchCommand,
  });

  final String pluginId;
  final Process process;
  final SandboxScratchDirectory scratch;
  final SandboxLaunchCommand launchCommand;

  bool _disposed = false;

  int get pid => process.pid;

  bool get isDisposed => _disposed;

  /// Forcefully terminates the child process (SIGKILL / TerminateProcess).
  Future<void> kill() async {
    if (_disposed) return;
    try {
      process.kill(ProcessSignal.sigkill);
    } catch (e) {
      debugPrint('SandboxProcessHandle.kill($pluginId): $e');
    }
    try {
      await process.exitCode.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // Process may already be gone.
    } catch (_) {
      // Ignore exit-code errors after kill.
    }
  }

  /// Kills the process (if still running) and deletes the scratch directory.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      process.kill(ProcessSignal.sigterm);
      try {
        await process.exitCode.timeout(const Duration(seconds: 2));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        try {
          await process.exitCode.timeout(const Duration(seconds: 1));
        } catch (_) {}
      } catch (_) {}
    } catch (e) {
      debugPrint('SandboxProcessHandle.dispose($pluginId) kill: $e');
    }
    await scratch.delete();
  }
}

/// Starts Level-2 OS process sandboxes for database-driver extensions.
///
/// Creates a scratch directory, builds a platform launch command
/// (`bwrap` / `sandbox-exec` / direct), and returns a [SandboxProcessHandle]
/// that owns process lifetime and scratch cleanup.
class SandboxProcessRunner {
  SandboxProcessRunner({
    this.bwrapAvailable,
    this.platformOverride,
    this.scratchBaseDirectory,
    this.processStarter = Process.start,
  });

  /// Override for tests / environments without bubblewrap.
  final bool? bwrapAvailable;

  /// Override `linux` / `macos` / `windows` for command-building tests.
  final String? platformOverride;

  /// Override system temp root for scratch directories (tests).
  final Directory? scratchBaseDirectory;

  /// Injectable [Process.start] for unit tests.
  final Future<Process> Function(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment,
    bool runInShell,
    ProcessStartMode mode,
  }) processStarter;

  /// Spawns [pluginExecutable] inside the OS sandbox for [pluginId].
  ///
  /// When OS sandboxing is unavailable, launch fails unless
  /// [allowUnsandboxedLaunch] is true (requires explicit user consent in UI).
  ///
  /// Credentials must never be passed via [pluginArguments] or [environment];
  /// use [SandboxCredentialsInjector] over Stdio JSON-RPC instead.
  Future<SandboxProcessHandle> start({
    required String pluginId,
    required String pluginExecutable,
    List<String> pluginArguments = const [],
    String? extensionRoot,
    SandboxCapabilities? capabilities,
    Map<String, String>? environment,
    bool allowUnsandboxedLaunch = false,
  }) async {
    SandboxSecretGuard.assertNoSecrets(
      arguments: pluginArguments,
      environment: environment ?? const {},
    );

    final scratch = await SandboxScratchDirectory.create(
      pluginId: pluginId,
      baseDirectory: scratchBaseDirectory,
    );

    final detected = bwrapAvailable ?? await detectBwrapAvailability();
    final usesBwrap = detected;
    if (bwrapAvailable == null && !usesBwrap) {
      debugPrint(
        'SandboxProcessRunner: bubblewrap unavailable or cannot set up user '
        'namespaces on this system; $pluginId requires consent to launch '
        'without OS sandbox.',
      );
    }
    final command = SandboxLaunchCommand.build(
      pluginExecutable: pluginExecutable,
      pluginArguments: pluginArguments,
      scratchPath: scratch.path,
      extensionRoot: extensionRoot,
      capabilities: capabilities,
      platformOverride: platformOverride,
      bwrapAvailable: usesBwrap,
    );

    final isolationIssue =
        SandboxOsIsolation.exceptionForLaunchCommand(command);
    if (isolationIssue != null && !allowUnsandboxedLaunch) {
      await scratch.delete();
      throw isolationIssue;
    }

    if (isolationIssue != null) {
      debugPrint(
        'SandboxProcessRunner: launching $pluginId without OS sandbox after '
        'explicit consent (${command.platform}).',
      );
    }

    // Never forward parent secrets via environment. Only pass an explicit map
    // (credentials go through Stdio JSON-RPC — Block E §5).
    final sanitizedEnv = <String, String>{
      'QUERYA_SANDBOX_SCRATCH': scratch.path,
      'QUERYA_SANDBOX_PLUGIN_ID': pluginId,
      if (environment != null) ...environment,
    };

    try {
      final process = await processStarter(
        command.executable,
        command.arguments,
        workingDirectory: scratch.path,
        environment: sanitizedEnv,
        includeParentEnvironment: false,
        runInShell: false,
        mode: ProcessStartMode.normal,
      );

      if (command.platform == 'windows') {
        debugPrint(
          'SandboxProcessRunner: Windows AppContainer/Job Object soft-start '
          'for $pluginId (pid=${process.pid}); full AppContainer lands with '
          'native helper.',
        );
      }

      return SandboxProcessHandle(
        pluginId: pluginId,
        process: process,
        scratch: scratch,
        launchCommand: command,
      );
    } catch (e) {
      await scratch.delete();
      rethrow;
    }
  }

  /// Whether [bwrap] is installed and can run a trivial command on this host.
  ///
  /// Some kernels/sessions deny user-namespace uid maps even when `which bwrap`
  /// succeeds; in that case we fall back to direct plugin execution.
  static Future<bool> detectBwrapAvailability() async {
    if (!Platform.isLinux) return false;
    try {
      final which = await Process.run('which', ['bwrap']);
      if (which.exitCode != 0) return false;

      final probe = await Process.run(
        'bwrap',
        const ['--ro-bind', '/', '/', '/bin/true'],
      );
      if (probe.exitCode != 0) {
        final detail = '${probe.stderr}'.trim();
        if (detail.isNotEmpty) {
          debugPrint('SandboxProcessRunner: bwrap probe failed: $detail');
        }
        return false;
      }
      return true;
    } catch (e) {
      debugPrint('SandboxProcessRunner: bwrap probe error: $e');
      return false;
    }
  }
}
