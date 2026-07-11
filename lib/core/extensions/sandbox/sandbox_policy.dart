import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';

/// Security policy limits for sandboxed extensions (Block E, section 3).
///
/// Validates that the `sandbox` block declared in a manifest does not request
/// more than the allowed policy for its [ExtensionType]. Used by
/// `LocalExtensionRegistry` when loading and `MarketplaceRepository.install()`
/// before registration.
class SandboxPolicy {
  SandboxPolicy._();

  /// Hard scratch directory quota, MB.
  static const maxScratchMb = 100;

  /// Hard RAM ceiling for heavy OLAP drivers, MB.
  static const maxMemoryMb = 512;

  /// Hard file descriptor ceiling.
  static const maxOpenFiles = 64;

  /// Returns a list of policy violations; empty means the manifest is allowed.
  static List<String> validate(ExtensionManifest manifest) {
    final sandbox = manifest.sandbox;
    if (sandbox == null) return const [];

    final errors = <String>[];
    final type = manifest.type;

    if (sandbox.engine == SandboxEngine.unknown) {
      errors.add('Unknown sandbox engine.');
    }

    if (sandbox.network.mode == NetworkPermissionMode.unknown) {
      errors.add('Unknown network permission mode.');
    }

    // OS process sandbox (Level 2) is reserved for database drivers.
    if (sandbox.engine == SandboxEngine.process &&
        type != ExtensionType.databaseDriver) {
      errors.add(
        'Sandbox engine "process" is only allowed for database drivers.',
      );
    }

    // Network sockets are only allowed for database drivers, and only to the
    // user-configured connection host.
    if (sandbox.network.mode == NetworkPermissionMode.connectionHostOnly &&
        type != ExtensionType.databaseDriver) {
      errors.add(
        'Network access is not allowed for extensions of type "${type.value}".',
      );
    }

    if (sandbox.filesystem.access != FilesystemPermission.scratchOnlyAccess) {
      errors.add(
        'Filesystem access "${sandbox.filesystem.access}" is not allowed; '
        'only "${FilesystemPermission.scratchOnlyAccess}" is supported.',
      );
    }

    if (sandbox.filesystem.scratchMb <= 0 ||
        sandbox.filesystem.scratchMb > maxScratchMb) {
      errors.add(
        'Scratch quota ${sandbox.filesystem.scratchMb} MB exceeds the '
        '$maxScratchMb MB limit.',
      );
    }

    if (sandbox.resources.memoryMb <= 0 ||
        sandbox.resources.memoryMb > maxMemoryMb) {
      errors.add(
        'Memory limit ${sandbox.resources.memoryMb} MB exceeds the '
        '$maxMemoryMb MB ceiling.',
      );
    }

    if (sandbox.resources.maxOpenFiles <= 0 ||
        sandbox.resources.maxOpenFiles > maxOpenFiles) {
      errors.add(
        'File descriptor limit ${sandbox.resources.maxOpenFiles} exceeds '
        'the $maxOpenFiles ceiling.',
      );
    }

    return errors;
  }

  static bool isAllowed(ExtensionManifest manifest) =>
      validate(manifest).isEmpty;
}
