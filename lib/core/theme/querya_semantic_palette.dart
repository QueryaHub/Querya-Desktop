import 'dart:ui';

import 'querya_theme.dart';

/// Semantic UI colors derived from the active Querya theme.
///
/// Feature widgets should use these roles instead of assigning meaning to
/// literal colors. The chart tokens intentionally provide a stable set of
/// distinct colors for data and type badges.
class QueryaSemanticPalette {
  const QueryaSemanticPalette({
    required this.action,
    required this.success,
    required this.destructive,
    required this.muted,
    required this.type1,
    required this.type2,
    required this.type3,
    required this.type4,
    required this.type5,
  });

  factory QueryaSemanticPalette.fromTheme(QueryaTheme theme) {
    final scheme = theme.colorScheme;
    final workbench = theme.workbench;
    return QueryaSemanticPalette(
      action: workbench.accent,
      success: workbench.success,
      destructive: workbench.destructive,
      muted: workbench.mutedForeground,
      type1: scheme.chart1,
      type2: scheme.chart2,
      type3: scheme.chart3,
      type4: scheme.chart4,
      type5: scheme.chart5,
    );
  }

  final Color action;
  final Color success;
  final Color destructive;
  final Color muted;
  final Color type1;
  final Color type2;
  final Color type3;
  final Color type4;
  final Color type5;
}
