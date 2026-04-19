import 'package:flutter/material.dart' as material;

import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/connections/new_connection_dialog.dart';
import 'package:querya_desktop/features/mongodb/mongodb_connection_form.dart';
import 'package:querya_desktop/features/mysql/mysql_connection_form.dart';
import 'package:querya_desktop/features/postgresql/postgresql_connection_form.dart';
import 'package:querya_desktop/features/redis/redis_connection_form.dart';

/// Picks a database type, opens the matching form, returns a saved row or null.
Future<ConnectionRow?> promptCreateConnection(
  material.BuildContext context, {
  int? folderId,
}) async {
  final type = await showNewConnectionDialog(context);
  if (type == null) return null;
  return switch (type) {
    ConnectionType.postgresql =>
      await showPostgresConnectionForm(context, folderId: folderId),
    ConnectionType.mysql =>
      await showMysqlConnectionForm(context, folderId: folderId),
    ConnectionType.mongodb =>
      await showMongoConnectionForm(context, folderId: folderId),
    ConnectionType.redis =>
      await showRedisConnectionForm(context, folderId: folderId),
  };
}
