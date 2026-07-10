import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/extensions/models/sandbox_capabilities.dart';
import 'package:querya_desktop/core/extensions/sandbox/sandbox_policy.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

/// Support matrix for locally installed / marketplace extensions.
///
/// Themes and Level-1 scripts install fully. Database drivers remain preview
/// listings until they declare a policy-compliant Level-2 `sandbox.engine:
/// process` block (Block E M3).
class ExtensionSupport {
  ExtensionSupport._();

  static const databaseDriverPreviewNotice =
      'Database drivers in the Marketplace are preview listings only until they '
      'declare a policy-compliant OS process sandbox. '
      'Querya connects using built-in Dart drivers (PostgreSQL, MySQL, SQLite, '
      'Redis, MongoDB). Sandboxed external drivers install when '
      '`sandbox.engine` is `process` and passes SandboxPolicy.';

  static const databaseDriverMissingEntryMessage =
      'Driver package is missing its main entry file. Installation aborted.';

  /// Type-level preview heuristic (drivers default to preview).
  /// Prefer [isPreviewOnlyManifest] when a full manifest is available.
  static bool isPreviewOnly(ExtensionType type) =>
      type == ExtensionType.databaseDriver;

  /// Drivers without a valid Level-2 process sandbox stay preview-only.
  /// Scripts / themes are always installable (subject to SandboxPolicy).
  static bool isPreviewOnlyManifest(ExtensionManifest manifest) {
    if (manifest.type != ExtensionType.databaseDriver) return false;
    final sandbox = manifest.sandbox;
    if (sandbox == null || sandbox.engine != SandboxEngine.process) {
      return true;
    }
    return !SandboxPolicy.isAllowed(manifest);
  }

  /// Ensures a database driver archive contains the declared [ExtensionManifest.main].
  static void validateDriverPackage({
    required ExtensionManifest manifest,
    required Directory installDir,
  }) {
    if (manifest.type != ExtensionType.databaseDriver) return;

    final main = manifest.main?.trim();
    if (main == null || main.isEmpty) {
      throw MarketplaceException(
        'Driver "${manifest.id}" is missing a main entry in manifest.json.',
      );
    }

    final entry = File(p.join(installDir.path, main));
    if (!entry.existsSync()) {
      throw MarketplaceException(
        'Driver package "${manifest.id}" is missing entry file "$main". '
        '$databaseDriverMissingEntryMessage',
      );
    }
  }
}
