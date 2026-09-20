import 'package:flutter/material.dart';

/// Shared connection-tree metrics and colors (PG / MySQL / SQLite / SDUI).
abstract final class QueryaTreeTokens {
  /// Indent for schema rows and sibling object folders under a database.
  static const double indent = 16;

  /// First level under a connection tile (Databases / root folder).
  static const double underConnection = 20;

  /// Leaf list indent (tables / views under an object folder).
  static const double leafList = 26;

  /// Compact **SERVERS** header top padding (UI-05).
  static const double serversHeaderTop = 12;

  /// Indent-guide stroke (UI-05).
  static const double guideWidth = 1;

  /// Horizontal offset of the guide inside each indent band.
  static const double guideInset = 8;

  /// Guide line alpha on [QueryaWorkbenchTheme.borderSubtle] / outline.
  static const double guideAlpha = 0.15;

  /// Loading / error inset under a connection expand (databases load).
  static const double errorConnection = 28;

  /// Nested loading / error inset (schemas under database, etc.).
  static const double errorNested = 24;

  /// Base left inset for SDUI expand errors before depth scaling.
  static const double errorSduiBase = 36;

  static const double spinnerConnection = 12;
  static const double spinnerNested = 10;
  static const double spinnerInline = 14;
  static const double spinnerStroke = 1.5;
  static const double spinnerStrokeInline = 2;

  static const EdgeInsets loadingPaddingConnection = EdgeInsets.only(
    left: errorConnection,
    top: 4,
    bottom: 4,
  );

  static const EdgeInsets loadingPaddingNested = EdgeInsets.only(
    left: errorNested,
    top: 2,
    bottom: 2,
  );

  static const EdgeInsets errorPaddingConnection = EdgeInsets.only(
    left: errorConnection,
    top: 4,
    bottom: 4,
  );

  static const EdgeInsets errorPaddingNested = EdgeInsets.only(
    left: errorNested,
    top: 4,
    bottom: 8,
  );

  static const EdgeInsets emptyFilterPadding = EdgeInsets.only(
    left: leafList,
    top: 4,
    bottom: 6,
  );

  /// SDUI expand-error inset: [errorSduiBase] + [depth] × [indent].
  static EdgeInsets errorPaddingForDepth(int depth) => EdgeInsets.only(
        left: errorSduiBase + depth * indent,
        top: 2,
        bottom: 2,
      );

  /// Leaf-row icon tint (tables, views, sequences, …).
  ///
  /// Takes [primary] (not [ColorScheme]) so both Material and shadcn schemes
  /// can pass `.primary` without a type clash.
  static Color leafIconColor(Color primary) =>
      primary.withValues(alpha: 0.5);
}
