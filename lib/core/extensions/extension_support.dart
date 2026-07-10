import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/market/marketplace_repository.dart';

/// Support matrix for locally installed / marketplace extensions.
///
/// Themes install and apply fully. Database drivers are catalog preview until
/// the dynamic plugin runtime ships (see Marketplace API roadmap).
class ExtensionSupport {
  ExtensionSupport._();

  static const databaseDriverPreviewNotice =
      'Database drivers in the Marketplace are preview listings only. '
      'Querya connects using built-in Dart drivers (PostgreSQL, MySQL, SQLite, '
      'Redis, MongoDB). External driver plugins will load via the Marketplace '
      'plugin runtime in a future release.';

  static const databaseDriverMissingEntryMessage =
      'Driver package is missing its main entry file. Installation aborted.';

  static bool isPreviewOnly(ExtensionType type) =>
      type == ExtensionType.databaseDriver;

  static bool isPreviewOnlyManifest(ExtensionManifest manifest) =>
      isPreviewOnly(manifest.type);

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
