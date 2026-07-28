import 'package:flutter/material.dart';

/// Shared connection-tree metrics and colors (PG / MySQL / SQLite / SDUI).
abstract final class QueryaTreeTokens {
  /// Indent for schema rows and sibling object folders under a database.
  static const double indent = 16;

  /// Leaf-row icon tint (tables, views, sequences, …).
  static Color leafIconColor(ColorScheme scheme) =>
      scheme.primary.withValues(alpha: 0.5);
}
