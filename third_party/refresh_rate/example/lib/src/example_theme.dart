import 'package:flutter/material.dart';

ThemeData buildExampleTheme() {
  const base = Color(0xFF131313);
  const panelHigh = Color(0xFF2A2A2A);
  const cyan = Color(0xFF00F0FF);
  const emerald = Color(0xFF36FF8B);
  const amber = Color(0xFFFFBA20);
  const text = Color(0xFFE5E2E1);
  const muted = Color(0xFFB9CACB);

  final scheme = const ColorScheme.dark(
    brightness: Brightness.dark,
    surface: base,
    primary: cyan,
    secondary: emerald,
    tertiary: amber,
    onSurface: text,
    onPrimary: Color(0xFF00363A),
    onSecondary: Color(0xFF003919),
    onTertiary: Color(0xFF412D00),
    outline: Color(0xFF3B494B),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: base,
    canvasColor: base,
    textTheme: ThemeData.dark().textTheme.apply(
          bodyColor: text,
          displayColor: text,
        ),
    chipTheme: ChipThemeData(
      backgroundColor: panelHigh,
      selectedColor: cyan.withValues(alpha: 0.16),
      side: BorderSide.none,
      labelStyle: const TextStyle(
        color: text,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: panelHigh,
        foregroundColor: text,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        side: BorderSide(color: cyan.withValues(alpha: 0.38)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
        ),
      ),
    ),
    dividerColor: muted.withValues(alpha: 0.08),
  );
}
