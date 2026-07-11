import 'package:flutter/material.dart' as material;

import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/connection_type_choice.dart';
import 'package:querya_desktop/features/connections/extension_connection_form.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'package:querya_desktop/features/connections/sqlite_connection_form.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/mysql/mysql_connection_form.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';

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
