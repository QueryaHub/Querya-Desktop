import 'package:flutter/material.dart';

import '../querya_theme.dart';
import 'apply_token_colors_to_editor.dart';
import 'querya_editor_theme_from_manifest.dart';
import 'querya_theme_color_scheme.dart';
import 'querya_theme_manifest.dart';
import 'querya_workbench_theme_from_manifest.dart';

/// Builds a [QueryaTheme] from a parsed Querya custom theme manifest.
QueryaTheme queryaThemeFromManifest(QueryaThemeManifest manifest) {
  final fallback =
      manifest.isLight ? QueryaTheme.lightDefault : QueryaTheme.darkDefault;
  final brightness =
      manifest.isLight ? Brightness.light : Brightness.dark;

  var editor = editorThemeFromQueryaColors(
    colors: manifest.editorColors,
    fallback: fallback.editor,
  );
  final workbench = workbenchThemeFromQueryaColors(
    colors: manifest.editorColors,
    fallback: fallback.workbench,
  );

  if (manifest.editorColors.containsKey('editorBackground') &&
      editor.background != workbench.editorBackground) {
    editor = editor.copyWith(background: workbench.editorBackground);
  }

  final tokenColors = manifest.tokenColors;
  if (tokenColors.isNotEmpty) {
    editor = applyTokenColorsToEditor(editor, tokenColors);
  }

  final colorScheme = colorSchemeFromQueryaThemeColors(
    colors: manifest.shadcnColors,
    fallback: fallback,
  );

  return fallback.copyWith(
    workbench: workbench,
    editor: editor,
    brightness: brightness,
    colorScheme: colorScheme,
    tokenColors: tokenColors,
  );
}
