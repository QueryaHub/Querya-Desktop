import 'dart:io';

import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';

/// Resolved argv for launching a plugin inside the OS process sandbox.
class SandboxLaunchCommand {
  const SandboxLaunchCommand({
    required this.executable,
    required this.arguments,
    required this.platform,
    this.usesOsSandbox = true,
  });

  /// Outer executable (`bwrap`, `sandbox-exec`, or the plugin binary itself).
  final String executable;

  /// Full argument list passed to [executable].
  final List<String> arguments;

  /// Platform this command was built for (`linux`, `macos`, `windows`, …).
  final String platform;

  /// Whether an OS-level sandbox wrapper is applied.
  final bool usesOsSandbox;

  /// Builds a platform-specific launch command.
  ///
  /// - **Linux:** `bwrap --unshare-all --share-net … -- <plugin> <args>`
  /// - **macOS:** `sandbox-exec -p <profile> <plugin> <args>`
  /// - **Windows:** direct process start (AppContainer/Job Object applied by
  ///   the runner after spawn; see [SandboxProcessRunner]).
  factory SandboxLaunchCommand.build({
    required String pluginExecutable,
    List<String> pluginArguments = const [],
    required String scratchPath,
    String? extensionRoot,
    SandboxCapabilities? capabilities,
    String? platformOverride,
    bool bwrapAvailable = true,
  }) {
    final platform = platformOverride ?? _currentPlatform;
    switch (platform) {
      case 'linux':
        return _linux(
          pluginExecutable: pluginExecutable,
          pluginArguments: pluginArguments,
          scratchPath: scratchPath,
          extensionRoot: extensionRoot,
          capabilities: capabilities,
          bwrapAvailable: bwrapAvailable,
        );
      case 'macos':
        return _macos(
          pluginExecutable: pluginExecutable,
          pluginArguments: pluginArguments,
          scratchPath: scratchPath,
          extensionRoot: extensionRoot,
        );
      case 'windows':
        return SandboxLaunchCommand(
          executable: pluginExecutable,
          arguments: List<String>.from(pluginArguments),
          platform: 'windows',
          // Soft isolation until native AppContainer helper lands.
          usesOsSandbox: false,
        );
      default:
        return SandboxLaunchCommand(
          executable: pluginExecutable,
          arguments: List<String>.from(pluginArguments),
          platform: platform,
          usesOsSandbox: false,
        );
    }
  }

  static String get _currentPlatform {
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return Platform.operatingSystem;
  }

  static SandboxLaunchCommand _linux({
    required String pluginExecutable,
    required List<String> pluginArguments,
    required String scratchPath,
    String? extensionRoot,
    SandboxCapabilities? capabilities,
    required bool bwrapAvailable,
  }) {
    if (!bwrapAvailable) {
      return SandboxLaunchCommand(
        executable: pluginExecutable,
        arguments: List<String>.from(pluginArguments),
        platform: 'linux',
        usesOsSandbox: false,
      );
    }

    final args = <String>[
      // Isolate all namespaces except network (DB drivers need TCP/TLS).
      '--unshare-all',
      '--share-net',
      '--die-with-parent',
      '--new-session',
      // Root filesystem read-only; scratch and (optional) extension root RW/RO.
      '--ro-bind', '/', '/',
      '--bind', scratchPath, scratchPath,
      '--chdir', scratchPath,
    ];

    if (extensionRoot != null && extensionRoot.isNotEmpty) {
      args.addAll(['--ro-bind', extensionRoot, extensionRoot]);
    }

    final maxOpenFiles =
        capabilities?.resources.maxOpenFiles ?? ResourceLimits.defaultMaxOpenFiles;
    // Soft hint via environment; hard ulimit applied by the runner when possible.
    args.addAll(['--setenv', 'QUERYA_SANDBOX_MAX_OPEN_FILES', '$maxOpenFiles']);
    args.addAll(['--setenv', 'QUERYA_SANDBOX_SCRATCH', scratchPath]);

    args.add('--');
    args.add(pluginExecutable);
    args.addAll(pluginArguments);

    return SandboxLaunchCommand(
      executable: 'bwrap',
      arguments: args,
      platform: 'linux',
    );
  }

  static SandboxLaunchCommand _macos({
    required String pluginExecutable,
    required List<String> pluginArguments,
    required String scratchPath,
    String? extensionRoot,
  }) {
    final profile = buildMacOsSeatbeltProfile(
      scratchPath: scratchPath,
      extensionRoot: extensionRoot,
    );
    return SandboxLaunchCommand(
      executable: 'sandbox-exec',
      arguments: [
        '-p',
        profile,
        pluginExecutable,
        ...pluginArguments,
      ],
      platform: 'macos',
    );
  }
}

/// Seatbelt (sandbox-exec) profile allowing network + scratch RW only.
String buildMacOsSeatbeltProfile({
  required String scratchPath,
  String? extensionRoot,
}) {
  final buffer = StringBuffer()
    ..writeln('(version 1)')
    ..writeln('(deny default)')
    ..writeln('(allow process*)')
    ..writeln('(allow sysctl-read)')
    ..writeln('(allow mach-lookup)')
    ..writeln('(allow network*)')
    ..writeln('(allow file-read*)')
    ..writeln('(allow file-write* (subpath "$scratchPath"))');
  if (extensionRoot != null && extensionRoot.isNotEmpty) {
    buffer.writeln('(allow file-read* (subpath "$extensionRoot"))');
  }
  return buffer.toString().trimRight();
}
