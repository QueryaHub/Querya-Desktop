import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'parser/vscode_theme_manifest.dart';
import 'querya_colors.dart';
import 'querya_editor_theme.dart';
import 'querya_workbench_theme.dart';

/// Full Querya theme: workbench chrome + editor tokens + shadcn [ColorScheme].
class QueryaTheme {
  const QueryaTheme({
    required this.workbench,
    required this.editor,
    required this.brightness,
    required this.colorScheme,
    this.tokenColors = const [],
  });

  final QueryaWorkbenchTheme workbench;
  final QueryaEditorTheme editor;
  final Brightness brightness;
  final ColorScheme colorScheme;

  /// VS Code `tokenColors` for syntax highlighting (imported themes).
  final List<TokenColorRule> tokenColors;

  static const QueryaTheme darkDefault = QueryaTheme(
    workbench: QueryaWorkbenchTheme.darkDefault,
    editor: QueryaEditorTheme.darkDefault,
    brightness: Brightness.dark,
    colorScheme: _darkColorScheme,
  );

  static const QueryaTheme lightDefault = QueryaTheme(
    workbench: QueryaWorkbenchTheme.lightDefault,
    editor: QueryaEditorTheme.lightDefault,
    brightness: Brightness.light,
    colorScheme: _lightColorScheme,
  );

  /// Matches [QueryaWorkbenchTheme.darkDefault] / legacy [QueryaColorScheme].
  static const ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    background: QueryaColors.canvas,
    foreground: Color(0xFFF8FAFC),
    card: QueryaColors.surface,
    cardForeground: Color(0xFFF8FAFC),
    popover: QueryaColors.surface,
    popoverForeground: Color(0xFFF8FAFC),
    primary: QueryaColors.accentCyan,
    primaryForeground: QueryaColors.onAccent,
    secondary: Color(0xFF18181B),
    secondaryForeground: Color(0xFFF8FAFC),
    muted: Color(0xFF18181B),
    mutedForeground: QueryaColors.mutedLabel,
    accent: Color(0xFF27272A),
    accentForeground: Color(0xFFF8FAFC),
    destructive: Color(0xFFEF4444),
    destructiveForeground: Color(0xFFF8FAFC),
    border: QueryaColors.borderSubtle,
    input: QueryaColors.borderSubtle,
    ring: QueryaColors.accentCyan,
    chart1: Color(0xFF2662D9),
    chart2: Color(0xFF2EB88A),
    chart3: Color(0xFFE88C30),
    chart4: Color(0xFFAF57DB),
    chart5: Color(0xFFE23670),
  );

  /// Matches [QueryaWorkbenchTheme.lightDefault].
  static const ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    background: Color(0xFFFAFAFA),
    foreground: Color(0xFF0F172A),
    card: Color(0xFFFFFFFF),
    cardForeground: Color(0xFF0F172A),
    popover: Color(0xFFFFFFFF),
    popoverForeground: Color(0xFF0F172A),
    primary: QueryaColors.accentCyan,
    primaryForeground: QueryaColors.onAccent,
    secondary: Color(0xFFF4F4F5),
    secondaryForeground: Color(0xFF0F172A),
    muted: Color(0xFFF4F4F5),
    mutedForeground: Color(0xFF64748B),
    accent: Color(0xFFE4E4E7),
    accentForeground: Color(0xFF0F172A),
    destructive: Color(0xFFDC2626),
    destructiveForeground: Color(0xFFF8FAFC),
    border: Color(0xFFE4E4E7),
    input: Color(0xFFE4E4E7),
    ring: QueryaColors.accentCyan,
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
    List<TokenColorRule>? tokenColors,
  }) {
    return QueryaTheme(
      workbench: workbench ?? this.workbench,
      editor: editor ?? this.editor,
      brightness: brightness ?? this.brightness,
      colorScheme: colorScheme ?? this.colorScheme,
      tokenColors: tokenColors ?? this.tokenColors,
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
      tokenColors: t < 0.5 ? a.tokenColors : b.tokenColors,
    );
  }

  ThemeData toShadcnThemeData({
    double radius = 0.58,
    double scaling = 1,
    Typography? typography,
  }) {
    final typo = typography ?? const Typography.geist();
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
          colorScheme == other.colorScheme &&
          _listEquals(tokenColors, other.tokenColors);

  @override
  int get hashCode =>
      Object.hash(workbench, editor, brightness, colorScheme, tokenColors);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
