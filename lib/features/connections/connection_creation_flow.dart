import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/extensions/extension_driver_catalog.dart';
import 'package:querya_desktop/core/extensions/models/extension_contributions.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/extension_connection_form.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/mysql/mysql_connection_form.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';
import 'package:querya_desktop/shared/widgets/app_toast.dart';

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
    if (manifest == null) {
      // Not a silent nothing (#1314): say what is missing.
      final who = existing.extensionId?.trim().isNotEmpty == true
          ? 'The extension "${existing.extensionId!.trim()}"'
          : 'The extension for "${existing.type}" connections';
      _explain(
        dialogContext,
        '$who that provides "${existing.name}" is not installed or is '
        'disabled. Install or enable it in the extension manager, then edit '
        'the connection.',
      );
      return null;
    }
    final driver = driverForConnection(existing, manifest.contributedDrivers);
    if (driver == null) {
      _explain(
        dialogContext,
        'The extension "${manifest.id}" no longer provides the driver '
        '"${existing.type}" that "${existing.name}" uses. Update or '
        'reinstall the extension to edit it.',
      );
      return null;
    }
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
    _ => _explainUnknownType(dialogContext, existing),
  };
}

ConnectionRow? _explainUnknownType(
  material.BuildContext context,
  ConnectionRow existing,
) {
  _explain(
    context,
    'Unknown connection type "${existing.type}": "${existing.name}" cannot '
    'be edited here.',
  );
  return null;
}

/// A short error toast on [context], when it is still mounted.
void _explain(material.BuildContext context, String message) {
  if (!context.mounted) return;
  showAppToast(
    context: context,
    variant: AppToastVariant.error,
    message: message,
  );
}

/// The driver of [row] in [drivers]: the one whose id is the row's type, or,
/// when the extension contributes exactly one, that one. Never a different
/// driver of an extension that has several (#1314).
@visibleForTesting
DriverContribution? driverForConnection(
  ConnectionRow row,
  Iterable<DriverContribution> drivers,
) {
  final type = row.type.trim().toLowerCase();
  final all = drivers.toList();
  for (final driver in all) {
    if (driver.driverId.trim().toLowerCase() == type) return driver;
  }
  return all.length == 1 ? all.single : null;
}
