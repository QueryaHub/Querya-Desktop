import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/ui/querya_icons.dart';

/// Database type for built-in new connections.
enum ConnectionType {
  postgresql,
  mysql,
  redis,
  mongodb,
  sqlite,
}

extension ConnectionTypeX on ConnectionType {
  String get label => switch (this) {
        ConnectionType.postgresql => 'PostgreSQL',
        ConnectionType.mysql => 'MySQL',
        ConnectionType.redis => 'Redis',
        ConnectionType.mongodb => 'MongoDB',
        ConnectionType.sqlite => 'SQLite',
      };

  material.IconData get icon => QueryaIcons.connectionIcon(name);

  /// Asset path for custom icon (from Downloads).
  String? get iconAsset => QueryaIcons.connectionAsset(name);

  bool get isSql =>
      this == ConnectionType.postgresql ||
      this == ConnectionType.mysql ||
      this == ConnectionType.sqlite;

  bool get isNoSql =>
      this == ConnectionType.redis || this == ConnectionType.mongodb;
}
