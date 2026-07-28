import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/extension_connection_form.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/mysql/mysql_connection_form.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';

export 'package:querya_desktop/features/connections/connection_edit_secrets.dart';

/// Context that stays mounted after menu overlays close (multi-step dialog flow).
material.BuildContext _dialogAnchorContext(material.BuildContext context) {
  final navigator = material.Navigator.maybeOf(context, rootNavigator: true);
  if (navigator != null && navigator.context.mounted) {
    return navigator.context;
  }
  return context;
}

/// Picks a database type, opens the matching form, returns a saved row or null.
Future<ConnectionRow?> promptCreateConnection(
  material.BuildContext context, {
  int? folderId,
}) async {
  final dialogContext = _dialogAnchorContext(context);
  final choice = await showNewConnectionDialog(dialogContext);
  if (choice == null) return null;
  if (!dialogContext.mounted) return null;

  return switch (choice) {
    BuiltInConnectionType(:final type) => switch (type) {
        ConnectionType.postgresql => dialogContext.mounted
            ? await showPostgresConnectionForm(
                dialogContext,
                folderId: folderId,
              )
            : null,
        ConnectionType.mysql => dialogContext.mounted
            ? await showMysqlConnectionForm(dialogContext, folderId: folderId)
            : null,
        ConnectionType.mongodb => dialogContext.mounted
            ? await showMongoConnectionForm(dialogContext, folderId: folderId)
            : null,
        ConnectionType.redis => dialogContext.mounted
            ? await showRedisConnectionForm(dialogContext, folderId: folderId)
            : null,
        ConnectionType.sqlite => dialogContext.mounted
            ? await showSqliteConnectionForm(dialogContext, folderId: folderId)
            : null,
      },
    ExtensionDriverChoice(:final manifest, :final driver) =>
      dialogContext.mounted
          ? await showExtensionConnectionForm(
              dialogContext,
              manifest: manifest,
              driver: driver,
              folderId: folderId,
            )
          : null,
  };
}

/// Opens the matching form prefilled for [existing] (type/driver fixed).
Future<ConnectionRow?> promptEditConnection(
  material.BuildContext context,
  ConnectionRow existing,
) async {
  final dialogContext = _dialogAnchorContext(context);
  if (!dialogContext.mounted) return null;

  if (ExtensionDriverCatalog.isExtensionDriverConnection(existing)) {
    final manifest = ExtensionDriverCatalog.manifestForConnection(existing);
    if (manifest == null) return null;
    final driver = _driverForConnection(existing, manifest.contributedDrivers);
    if (driver == null) return null;
    return showExtensionConnectionForm(
      dialogContext,
      manifest: manifest,
      driver: driver,
      folderId: existing.folderId,
      initial: existing,
    );
  }

  return switch (existing.type) {
    'postgresql' => showPostgresConnectionForm(
        dialogContext,
        folderId: existing.folderId,
        initial: existing,
      ),
    'mysql' => showMysqlConnectionForm(
        dialogContext,
        folderId: existing.folderId,
        initial: existing,
      ),
    'mongodb' => showMongoConnectionForm(
        dialogContext,
        folderId: existing.folderId,
        initial: existing,
      ),
    'redis' => showRedisConnectionForm(
        dialogContext,
        folderId: existing.folderId,
        initial: existing,
      ),
    'sqlite' => showSqliteConnectionForm(
        dialogContext,
        folderId: existing.folderId,
        initial: existing,
      ),
    _ => null,
  };
}

DriverContribution? _driverForConnection(
  ConnectionRow row,
  Iterable<DriverContribution> drivers,
) {
  final type = row.type.trim().toLowerCase();
  DriverContribution? first;
  for (final driver in drivers) {
    first ??= driver;
    if (driver.driverId.trim().toLowerCase() == type) return driver;
  }
  return first;
}
