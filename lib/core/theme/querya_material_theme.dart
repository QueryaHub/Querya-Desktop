import 'package:flutter/material.dart' as material;
import 'package:shadcn_flutter/shadcn_flutter.dart' show ColorScheme;

/// Material [ThemeData] aligned with Querya [ColorScheme] for dialogs, dropdowns, etc.
material.ThemeData materialThemeFromQuerya(ColorScheme scheme) {
  final materialScheme = material.ColorScheme(
    brightness: scheme.brightness,
    primary: scheme.primary,
    onPrimary: scheme.primaryForeground,
    secondary: scheme.secondary,
    onSecondary: scheme.secondaryForeground,
    surface: scheme.popover,
    onSurface: scheme.popoverForeground,
    error: scheme.destructive,
    onError: scheme.primaryForeground,
    outline: scheme.border,
  );

  final body = material.TextStyle(color: scheme.popoverForeground);
  final muted = material.TextStyle(color: scheme.mutedForeground);

  return material.ThemeData(
    useMaterial3: true,
    colorScheme: materialScheme,
    dialogTheme: material.DialogThemeData(backgroundColor: scheme.popover),
    textTheme: material.TextTheme(
      bodyLarge: body,
      bodyMedium: body,
      bodySmall: muted,
      titleLarge: body.copyWith(fontWeight: material.FontWeight.w600),
      titleMedium: body.copyWith(fontWeight: material.FontWeight.w600),
      labelLarge: body,
    ),
    dropdownMenuTheme: material.DropdownMenuThemeData(
      textStyle: body,
      menuStyle: material.MenuStyle(
        backgroundColor: material.WidgetStatePropertyAll(scheme.popover),
        surfaceTintColor: material.WidgetStatePropertyAll(scheme.popover),
      ),
    ),
  );
}
