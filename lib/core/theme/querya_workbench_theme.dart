import 'dart:ui';

import 'querya_colors.dart';

/// Workbench (non-editor) color tokens — sidebar, chrome, status, git decorations.
class QueryaWorkbenchTheme {
  const QueryaWorkbenchTheme({
    required this.canvas,
    required this.surface,
    required this.sidebarBackground,
    required this.editorBackground,
    required this.borderSubtle,
    required this.accent,
    required this.onAccent,
    required this.mutedForeground,
    required this.destructive,
    required this.success,
    required this.warning,
    required this.gitModified,
    required this.gitUntracked,
  });

  final Color canvas;
  final Color surface;
  final Color sidebarBackground;
  final Color editorBackground;
  final Color borderSubtle;
  final Color accent;
  final Color onAccent;
  final Color mutedForeground;
  final Color destructive;
  final Color success;
  final Color warning;
  final Color gitModified;
  final Color gitUntracked;

  /// Matches current [QueryaColors] / dark UI.
  static const QueryaWorkbenchTheme darkDefault = QueryaWorkbenchTheme(
    canvas: QueryaColors.canvas,
    surface: QueryaColors.surface,
    sidebarBackground: QueryaColors.canvas,
    editorBackground: QueryaColors.surface,
    borderSubtle: QueryaColors.borderSubtle,
    accent: QueryaColors.accentCyan,
    onAccent: QueryaColors.onAccent,
    mutedForeground: QueryaColors.mutedLabel,
    destructive: Color(0xFFEF4444),
    success: Color(0xFF4CAF50),
    warning: Color(0xFFE88C30),
    gitModified: Color(0xFFE88C30),
    gitUntracked: Color(0xFF2EB88A),
  );

  /// Built-in light preset (slate-like canvas, cyan brand accent).
  static const QueryaWorkbenchTheme lightDefault = QueryaWorkbenchTheme(
    canvas: Color(0xFFFAFAFA),
    surface: Color(0xFFFFFFFF),
    sidebarBackground: Color(0xFFF4F4F5),
    editorBackground: Color(0xFFFFFFFF),
    borderSubtle: Color(0xFFE4E4E7),
    accent: QueryaColors.accentCyan,
    onAccent: QueryaColors.onAccent,
    mutedForeground: Color(0xFF64748B),
    destructive: Color(0xFFDC2626),
    success: Color(0xFF16A34A),
    warning: Color(0xFFD97706),
    gitModified: Color(0xFFD97706),
    gitUntracked: Color(0xFF16A34A),
  );

  QueryaWorkbenchTheme copyWith({
    Color? canvas,
    Color? surface,
    Color? sidebarBackground,
    Color? editorBackground,
    Color? borderSubtle,
    Color? accent,
    Color? onAccent,
    Color? mutedForeground,
    Color? destructive,
    Color? success,
    Color? warning,
    Color? gitModified,
    Color? gitUntracked,
  }) {
    return QueryaWorkbenchTheme(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      sidebarBackground: sidebarBackground ?? this.sidebarBackground,
      editorBackground: editorBackground ?? this.editorBackground,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      accent: accent ?? this.accent,
      onAccent: onAccent ?? this.onAccent,
      mutedForeground: mutedForeground ?? this.mutedForeground,
      destructive: destructive ?? this.destructive,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      gitModified: gitModified ?? this.gitModified,
      gitUntracked: gitUntracked ?? this.gitUntracked,
    );
  }

  static QueryaWorkbenchTheme lerp(
    QueryaWorkbenchTheme a,
    QueryaWorkbenchTheme b,
    double t,
  ) {
    Color c(Color x, Color y) => Color.lerp(x, y, t)!;
    return QueryaWorkbenchTheme(
      canvas: c(a.canvas, b.canvas),
      surface: c(a.surface, b.surface),
      sidebarBackground: c(a.sidebarBackground, b.sidebarBackground),
      editorBackground: c(a.editorBackground, b.editorBackground),
      borderSubtle: c(a.borderSubtle, b.borderSubtle),
      accent: c(a.accent, b.accent),
      onAccent: c(a.onAccent, b.onAccent),
      mutedForeground: c(a.mutedForeground, b.mutedForeground),
      destructive: c(a.destructive, b.destructive),
      success: c(a.success, b.success),
      warning: c(a.warning, b.warning),
      gitModified: c(a.gitModified, b.gitModified),
      gitUntracked: c(a.gitUntracked, b.gitUntracked),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QueryaWorkbenchTheme &&
          canvas == other.canvas &&
          surface == other.surface &&
          sidebarBackground == other.sidebarBackground &&
          editorBackground == other.editorBackground &&
          borderSubtle == other.borderSubtle &&
          accent == other.accent &&
          onAccent == other.onAccent &&
          mutedForeground == other.mutedForeground &&
          destructive == other.destructive &&
          success == other.success &&
          warning == other.warning &&
          gitModified == other.gitModified &&
          gitUntracked == other.gitUntracked;

  @override
  int get hashCode => Object.hash(
        canvas,
        surface,
        sidebarBackground,
        editorBackground,
        borderSubtle,
        accent,
        onAccent,
        mutedForeground,
        destructive,
        success,
        warning,
        gitModified,
        gitUntracked,
      );
}
