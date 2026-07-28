import 'package:flutter/material.dart';

/// Shared connection-tree metrics and colors (PG / MySQL / SQLite / SDUI).
abstract final class QueryaTreeTokens {
  /// Indent for schema rows and sibling object folders under a database.
  static const double indent = 16;

  /// Leaf-row icon tint (tables, views, sequences, …).
  ///
  /// Takes [primary] (not [ColorScheme]) so both Material and shadcn schemes
  /// can pass `.primary` without a type clash.
  static Color leafIconColor(Color primary) =>
      primary.withValues(alpha: 0.5);
}
