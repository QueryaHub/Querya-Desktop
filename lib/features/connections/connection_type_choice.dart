import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/extensions/models/extension_manifest.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';

/// Result of the New Connection type picker (built-in or extension driver).
sealed class ConnectionTypeChoice {
  const ConnectionTypeChoice();

  String get label;
  material.IconData get icon;
  String? get iconAsset;
}

/// One of the five built-in Dart drivers.
final class BuiltInConnectionType extends ConnectionTypeChoice {
  const BuiltInConnectionType(this.type);

  final ConnectionType type;

  @override
  String get label => type.label;

  @override
  material.IconData get icon => type.icon;

  @override
  String? get iconAsset => type.iconAsset;

  @override
  bool operator ==(Object other) =>
      other is BuiltInConnectionType && other.type == type;

  @override
  int get hashCode => type.hashCode;
}

/// A driver contributed by an installed `database_driver` extension.
final class ExtensionDriverChoice extends ConnectionTypeChoice {
  const ExtensionDriverChoice({
    required this.manifest,
    required this.driver,
  });

  final ExtensionManifest manifest;
  final DriverContribution driver;

  @override
  String get label =>
      driver.displayName.isNotEmpty ? driver.displayName : manifest.name;

  @override
  material.IconData get icon => material.Icons.extension_rounded;

  @override
  String? get iconAsset => null;

  @override
  bool operator ==(Object other) =>
      other is ExtensionDriverChoice &&
      other.manifest.id == manifest.id &&
      other.driver.driverId == driver.driverId;

  @override
  int get hashCode => Object.hash(manifest.id, driver.driverId);
}
