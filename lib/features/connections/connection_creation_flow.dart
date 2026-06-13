import 'package:flutter/material.dart' as material;

import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
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
  final type = await showNewConnectionDialog(dialogContext);
  if (type == null) return null;
  if (!dialogContext.mounted) return null;
  switch (type) {
    case ConnectionType.postgresql:
      return await showPostgresConnectionForm(dialogContext, folderId: folderId);
    case ConnectionType.mysql:
      return await showMysqlConnectionForm(dialogContext, folderId: folderId);
    case ConnectionType.mongodb:
      return await showMongoConnectionForm(dialogContext, folderId: folderId);
    case ConnectionType.redis:
      return await showRedisConnectionForm(dialogContext, folderId: folderId);
  }
}
