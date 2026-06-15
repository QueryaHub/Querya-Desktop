import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../querya_workbench_theme.dart';
import 'color_parser.dart';

/// Workbench keys accepted in Querya custom `editor_colors`.
///
/// Editor syntax/surface keys are mapped separately by [editorThemeFromQueryaColors].
/// The generic `background` key is intentionally not mapped to canvas/editorBackground.
const _knownWorkbenchColorKeys = {
  'canvas',
  'surface',
  'sidebarBackground',
  'editorBackground',
  'mutedForeground',
  'accent',
  'onAccent',
  'borderSubtle',
  'destructive',
  'success',
  'warning',
  'gitModified',
  'gitUntracked',
};

/// Builds [QueryaWorkbenchTheme] from Querya custom `editor_colors`.
///
/// Missing keys and invalid optional colors fall back to [fallback].
QueryaWorkbenchTheme workbenchThemeFromQueryaColors({
  required Map<String, String> colors,
  required QueryaWorkbenchTheme fallback,
}) {
  if (kDebugMode) {
    for (final key in colors.keys) {
      if (!_knownWorkbenchColorKeys.contains(key)) {
        debugPrint('Querya theme: ignored editor_colors workbench key "$key"');
      }
    }
  }

  Color pick(String key, Color defaultValue) {
    final raw = colors[key];
    if (raw == null) return defaultValue;
    try {
      return parseQueryaThemeColor(raw);
    } on FormatException {
      if (kDebugMode) {
        debugPrint('Querya theme: invalid editor_colors."$key": $raw');
      }
      return defaultValue;
    }
  }

  return fallback.copyWith(
    canvas: pick('canvas', fallback.canvas),
    surface: pick('surface', fallback.surface),
    sidebarBackground: pick('sidebarBackground', fallback.sidebarBackground),
    editorBackground: pick('editorBackground', fallback.editorBackground),
    mutedForeground: pick('mutedForeground', fallback.mutedForeground),
    accent: pick('accent', fallback.accent),
    onAccent: pick('onAccent', fallback.onAccent),
    borderSubtle: pick('borderSubtle', fallback.borderSubtle),
    destructive: pick('destructive', fallback.destructive),
    success: pick('success', fallback.success),
    warning: pick('warning', fallback.warning),
    gitModified: pick('gitModified', fallback.gitModified),
    gitUntracked: pick('gitUntracked', fallback.gitUntracked),
  );
}
