import 'package:querya_desktop/core/extensions/local_extension_registry.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/core/extensions/models/extension_type.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';

/// Built-in + installed extension drivers for New Connection / Driver Manager.
class ExtensionDriverCatalog {
  ExtensionDriverCatalog._();

  static const builtInChoices = <ConnectionTypeChoice>[
    BuiltInConnectionType(ConnectionType.postgresql),
    BuiltInConnectionType(ConnectionType.mysql),
    BuiltInConnectionType(ConnectionType.sqlite),
    BuiltInConnectionType(ConnectionType.redis),
    BuiltInConnectionType(ConnectionType.mongodb),
  ];

  static const sqlBuiltIns = <ConnectionTypeChoice>[
    BuiltInConnectionType(ConnectionType.postgresql),
    BuiltInConnectionType(ConnectionType.mysql),
    BuiltInConnectionType(ConnectionType.sqlite),
  ];

  static const noSqlBuiltIns = <ConnectionTypeChoice>[
    BuiltInConnectionType(ConnectionType.redis),
    BuiltInConnectionType(ConnectionType.mongodb),
  ];

  /// Extension drivers currently loaded in [LocalExtensionRegistry].
  static List<ExtensionDriverChoice> extensionChoices([
    LocalExtensionRegistry? registry,
  ]) {
    final manifests = (registry ?? LocalExtensionRegistry.instance).manifests;
    final out = <ExtensionDriverChoice>[];
    for (final manifest in manifests) {
      if (manifest.type != ExtensionType.databaseDriver) continue;
      for (final driver in manifest.contributedDrivers) {
        if (driver.driverId.trim().isEmpty) continue;
        out.add(ExtensionDriverChoice(manifest: manifest, driver: driver));
      }
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  /// All choices for the "All databases" category.
  static List<ConnectionTypeChoice> allChoices([
    LocalExtensionRegistry? registry,
  ]) =>
      [...builtInChoices, ...extensionChoices(registry)];

  static List<ConnectionTypeChoice> sqlChoices([
    LocalExtensionRegistry? registry,
  ]) =>
      [...sqlBuiltIns, ...extensionChoices(registry)];

  static List<ConnectionTypeChoice> noSqlChoices() => noSqlBuiltIns;

  /// True when [row] is backed by an installed extension driver package.
  static bool isExtensionDriverConnection(ConnectionRow row) {
    final extId = row.extensionId?.trim();
    if (extId != null && extId.isNotEmpty) return true;
    return manifestForConnection(row) != null;
  }

  /// Resolves the installed manifest for a saved connection row.
  static ExtensionManifest? manifestForConnection(
    ConnectionRow row, [
    LocalExtensionRegistry? registry,
  ]) {
    final reg = registry ?? LocalExtensionRegistry.instance;
    final extId = row.extensionId?.trim();
    if (extId != null && extId.isNotEmpty) {
      for (final manifest in reg.manifests) {
        if (manifest.id == extId) return manifest;
      }
    }
    final type = row.type.trim().toLowerCase();
    if (type.isEmpty) return null;
    for (final manifest in reg.manifests) {
      if (manifest.type != ExtensionType.databaseDriver) continue;
      for (final driver in manifest.contributedDrivers) {
        if (driver.driverId.trim().toLowerCase() == type) {
          return manifest;
        }
      }
    }
    return null;
  }

  /// Packaged icon path for a saved connection, when available on disk.
  static String? iconFileForConnection(
    ConnectionRow row, [
    LocalExtensionRegistry? registry,
  ]) =>
      manifestForConnection(row, registry)?.resolvedIconPath;
}
