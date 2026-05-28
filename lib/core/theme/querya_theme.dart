import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_editor_theme.dart';
import 'querya_workbench_theme.dart';

/// Full Querya theme: workbench chrome + editor tokens + shadcn [ColorScheme].
class QueryaTheme {
  const QueryaTheme({
    required this.workbench,
    required this.editor,
    required this.brightness,
    required this.colorScheme,
  });

  final QueryaWorkbenchTheme workbench;
  final QueryaEditorTheme editor;
  final Brightness brightness;
  final ColorScheme colorScheme;

  static final QueryaTheme darkDefault = QueryaTheme(
    workbench: QueryaWorkbenchTheme.darkDefault,
    editor: QueryaEditorTheme.darkDefault,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme,
  );

  static final QueryaTheme lightDefault = QueryaTheme(
    workbench: QueryaWorkbenchTheme.lightDefault,
    editor: QueryaEditorTheme.lightDefault,
    brightness: Brightness.light,
    colorScheme: _lightColorScheme,
  );

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    background: QueryaWorkbenchTheme.darkDefault.canvas,
    foreground: Color(0xFFF8FAFC),
    card: QueryaWorkbenchTheme.darkDefault.surface,
    cardForeground: Color(0xFFF8FAFC),
    popover: QueryaWorkbenchTheme.darkDefault.surface,
    popoverForeground: Color(0xFFF8FAFC),
    primary: QueryaWorkbenchTheme.darkDefault.accent,
    primaryForeground: QueryaWorkbenchTheme.darkDefault.onAccent,
    secondary: Color(0xFF18181B),
    secondaryForeground: Color(0xFFF8FAFC),
    muted: Color(0xFF18181B),
    mutedForeground: QueryaWorkbenchTheme.darkDefault.mutedForeground,
    accent: Color(0xFF27272A),
    accentForeground: Color(0xFFF8FAFC),
    destructive: QueryaWorkbenchTheme.darkDefault.destructive,
    destructiveForeground: Color(0xFFF8FAFC),
    border: QueryaWorkbenchTheme.darkDefault.borderSubtle,
    input: QueryaWorkbenchTheme.darkDefault.borderSubtle,
    ring: QueryaWorkbenchTheme.darkDefault.accent,
    chart1: Color(0xFF2662D9),
    chart2: Color(0xFF2EB88A),
    chart3: Color(0xFFE88C30),
    chart4: Color(0xFFAF57DB),
    chart5: Color(0xFFE23670),
  );

  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    background: QueryaWorkbenchTheme.lightDefault.canvas,
    foreground: Color(0xFF0F172A),
    card: QueryaWorkbenchTheme.lightDefault.surface,
    cardForeground: Color(0xFF0F172A),
    popover: QueryaWorkbenchTheme.lightDefault.surface,
    popoverForeground: Color(0xFF0F172A),
    primary: QueryaWorkbenchTheme.lightDefault.accent,
    primaryForeground: QueryaWorkbenchTheme.lightDefault.onAccent,
    secondary: Color(0xFFF4F4F5),
    secondaryForeground: Color(0xFF0F172A),
    muted: Color(0xFFF4F4F5),
    mutedForeground: QueryaWorkbenchTheme.lightDefault.mutedForeground,
    accent: Color(0xFFE4E4E7),
    accentForeground: Color(0xFF0F172A),
    destructive: QueryaWorkbenchTheme.lightDefault.destructive,
    destructiveForeground: Color(0xFFF8FAFC),
    border: QueryaWorkbenchTheme.lightDefault.borderSubtle,
    input: QueryaWorkbenchTheme.lightDefault.borderSubtle,
    ring: QueryaWorkbenchTheme.lightDefault.accent,
    chart1: Color(0xFF2662D9),
    chart2: Color(0xFF2EB88A),
    chart3: Color(0xFFE88C30),
    chart4: Color(0xFFAF57DB),
    chart5: Color(0xFFE23670),
  );

  /// Builds [ColorScheme] from [workbench] (for imported / overridden themes).
  static ColorScheme colorSchemeFromWorkbench(
    QueryaWorkbenchTheme w, {
    required Brightness brightness,
  }) {
    final isDark = brightness == Brightness.dark;
    final fg = isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
    return ColorScheme(
      brightness: brightness,
      background: w.canvas,
      foreground: fg,
      card: w.surface,
      cardForeground: fg,
      popover: w.surface,
      popoverForeground: fg,
      primary: w.accent,
      primaryForeground: w.onAccent,
      secondary: isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
      secondaryForeground: fg,
      muted: isDark ? const Color(0xFF18181B) : const Color(0xFFF4F4F5),
      mutedForeground: w.mutedForeground,
      accent: isDark ? const Color(0xFF27272A) : const Color(0xFFE4E4E7),
      accentForeground: fg,
      destructive: w.destructive,
      destructiveForeground: const Color(0xFFF8FAFC),
      border: w.borderSubtle,
      input: w.borderSubtle,
      ring: w.accent,
      chart1: const Color(0xFF2662D9),
      chart2: const Color(0xFF2EB88A),
      chart3: const Color(0xFFE88C30),
      chart4: const Color(0xFFAF57DB),
      chart5: const Color(0xFFE23670),
    );
  }

  QueryaTheme copyWith({
    QueryaWorkbenchTheme? workbench,
    QueryaEditorTheme? editor,
    Brightness? brightness,
    ColorScheme? colorScheme,
  }) {
    return QueryaTheme(
      workbench: workbench ?? this.workbench,
      editor: editor ?? this.editor,
      brightness: brightness ?? this.brightness,
      colorScheme: colorScheme ?? this.colorScheme,
    );
  }

  static QueryaTheme lerp(QueryaTheme a, QueryaTheme b, double t) {
    final w = QueryaWorkbenchTheme.lerp(a.workbench, b.workbench, t);
    final e = QueryaEditorTheme.lerp(a.editor, b.editor, t);
    final brightness = t < 0.5 ? a.brightness : b.brightness;
    return QueryaTheme(
      workbench: w,
      editor: e,
      brightness: brightness,
      colorScheme: ColorScheme.lerp(a.colorScheme, b.colorScheme, t),
    );
  }

  ThemeData toShadcnThemeData({
    double radius = 0.58,
    double scaling = 1,
    Typography? typography,
  }) {
    final typo = typography ?? Typography.geist();
    final base = brightness == Brightness.dark
        ? ThemeData.dark(colorScheme: colorScheme)
        : ThemeData(colorScheme: colorScheme);
    return base.copyWith(
      radius: () => radius,
      scaling: () => scaling,
      typography: () => typo,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryaTheme &&
          workbench == other.workbench &&
          editor == other.editor &&
          brightness == other.brightness &&
          colorScheme == other.colorScheme;

  @override
  int get hashCode =>
      Object.hash(workbench, editor, brightness, colorScheme);
}
