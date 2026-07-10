import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_launch_command.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_scratch_directory.dart';

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
  Future<SandboxProcessHandle> start({
    required String pluginId,
    required String pluginExecutable,
    List<String> pluginArguments = const [],
    String? extensionRoot,
    SandboxCapabilities? capabilities,
    Map<String, String>? environment,
  }) async {
    final scratch = await SandboxScratchDirectory.create(
      pluginId: pluginId,
      baseDirectory: scratchBaseDirectory,
    );

    final usesBwrap = bwrapAvailable ?? await _detectBwrap();
    final command = SandboxLaunchCommand.build(
      pluginExecutable: pluginExecutable,
      pluginArguments: pluginArguments,
      scratchPath: scratch.path,
      extensionRoot: extensionRoot,
      capabilities: capabilities,
      platformOverride: platformOverride,
      bwrapAvailable: usesBwrap,
    );

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

  static Future<bool> _detectBwrap() async {
    if (!Platform.isLinux) return false;
    try {
      final result = await Process.run('which', ['bwrap']);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
