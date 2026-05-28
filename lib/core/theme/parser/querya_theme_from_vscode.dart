import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../querya_editor_theme.dart';
import '../querya_theme.dart';
import '../querya_workbench_theme.dart';
import 'color_parser.dart';
import 'vscode_color_map.dart';
import 'vscode_theme_manifest.dart';

/// Builds a [QueryaTheme] from a parsed VS Code manifest.
///
/// Missing keys keep values from [fallback] (defaults by manifest `type`).
QueryaTheme buildQueryaThemeFromVsCodeManifest(
  VsCodeThemeManifest manifest, {
  QueryaTheme? fallback,
  void Function(String unknownVsCodeKey)? onUnknownColorKey,
}) {
  final base = fallback ?? _defaultFallbackFor(manifest);
  final brightness = _brightnessFrom(manifest, base);

  var workbench = base.workbench;
  var editor = base.editor;
  Color? schemeForeground;
  Color? schemeBackground;
  Color? schemeCard;
  Color? schemeBorder;
  Color? schemeInput;
  Color? schemeRing;
  Color? schemeMutedForeground;
  Color? schemeAccent;

  for (final entry in manifest.colors.entries) {
    final target = kVsCodeColorMap[entry.key];
    if (target == null) {
      onUnknownColorKey?.call(entry.key);
      if (kDebugMode) {
        debugPrint('VsCode theme: ignored color key "${entry.key}"');
      }
      continue;
    }

    final Color color;
    try {
      color = parseVsCodeColor(entry.value);
    } on FormatException {
      if (kDebugMode) {
        debugPrint(
          'VsCode theme: invalid color for "${entry.key}": ${entry.value}',
        );
      }
      continue;
    }

    if (target.workbench != null) {
      workbench = _applyWorkbenchField(workbench, target.workbench!, color);
      if (target.workbench == VsCodeWorkbenchField.editorBackground) {
        editor = editor.copyWith(background: color);
      }
    } else if (target.editor != null) {
      editor = _applyEditorField(editor, target.editor!, color);
    } else if (target.colorScheme != null) {
      switch (target.colorScheme!) {
        case VsCodeColorSchemeField.foreground:
          schemeForeground = color;
        case VsCodeColorSchemeField.background:
          schemeBackground = color;
        case VsCodeColorSchemeField.card:
          schemeCard = color;
        case VsCodeColorSchemeField.border:
          schemeBorder = color;
        case VsCodeColorSchemeField.input:
          schemeInput = color;
        case VsCodeColorSchemeField.ring:
          schemeRing = color;
        case VsCodeColorSchemeField.mutedForeground:
          schemeMutedForeground = color;
        case VsCodeColorSchemeField.accent:
          schemeAccent = color;
      }
    }
  }

  if (editor.background != workbench.editorBackground) {
    editor = editor.copyWith(background: workbench.editorBackground);
  }

  var colorScheme = QueryaTheme.colorSchemeFromWorkbench(
    workbench,
    brightness: brightness,
  );

  final editorForegroundChanged =
      editor.foreground != base.editor.foreground;
  if (schemeForeground != null || editorForegroundChanged) {
    final fg = schemeForeground ?? editor.foreground;
    colorScheme = colorScheme.copyWith(
      foreground: () => fg,
      cardForeground: () => fg,
      popoverForeground: () => fg,
    );
  }
  if (schemeBackground != null) {
    colorScheme = colorScheme.copyWith(background: () => schemeBackground!);
  }
  if (schemeCard != null) {
    colorScheme = colorScheme.copyWith(
      card: () => schemeCard!,
      popover: () => schemeCard!,
    );
  }
  if (schemeBorder != null) {
    colorScheme = colorScheme.copyWith(border: () => schemeBorder!);
  }
  if (schemeInput != null) {
    colorScheme = colorScheme.copyWith(input: () => schemeInput!);
  }
  if (schemeRing != null) {
    colorScheme = colorScheme.copyWith(ring: () => schemeRing!);
  }
  if (schemeMutedForeground != null) {
    colorScheme = colorScheme.copyWith(
      mutedForeground: () => schemeMutedForeground!,
    );
  }
  if (schemeAccent != null) {
    colorScheme = colorScheme.copyWith(accent: () => schemeAccent!);
  }

  return QueryaTheme(
    workbench: workbench,
    editor: editor,
    brightness: brightness,
    colorScheme: colorScheme,
  );
}

QueryaTheme _defaultFallbackFor(VsCodeThemeManifest manifest) {
  if (manifest.isLight) return QueryaTheme.lightDefault;
  if (manifest.isDark) return QueryaTheme.darkDefault;
  return QueryaTheme.darkDefault;
}

Brightness _brightnessFrom(VsCodeThemeManifest manifest, QueryaTheme base) {
  if (manifest.isLight) return Brightness.light;
  if (manifest.isDark) return Brightness.dark;
  return base.brightness;
}

QueryaWorkbenchTheme _applyWorkbenchField(
  QueryaWorkbenchTheme w,
  VsCodeWorkbenchField field,
  Color color,
) {
  switch (field) {
    case VsCodeWorkbenchField.canvas:
      return w.copyWith(canvas: color);
    case VsCodeWorkbenchField.surface:
      return w.copyWith(surface: color);
    case VsCodeWorkbenchField.sidebarBackground:
      return w.copyWith(sidebarBackground: color);
    case VsCodeWorkbenchField.editorBackground:
      return w.copyWith(editorBackground: color);
    case VsCodeWorkbenchField.borderSubtle:
      return w.copyWith(borderSubtle: color);
    case VsCodeWorkbenchField.accent:
      return w.copyWith(accent: color);
    case VsCodeWorkbenchField.mutedForeground:
      return w.copyWith(mutedForeground: color);
    case VsCodeWorkbenchField.gitModified:
      return w.copyWith(gitModified: color);
    case VsCodeWorkbenchField.gitUntracked:
      return w.copyWith(gitUntracked: color);
  }
}

QueryaEditorTheme _applyEditorField(
  QueryaEditorTheme e,
  VsCodeEditorField field,
  Color color,
) {
  switch (field) {
    case VsCodeEditorField.background:
      return e.copyWith(background: color);
    case VsCodeEditorField.foreground:
      return e.copyWith(foreground: color);
    case VsCodeEditorField.selection:
      return e.copyWith(selection: color);
    case VsCodeEditorField.lineNumber:
      return e.copyWith(lineNumber: color);
    case VsCodeEditorField.bracketMatch:
      return e.copyWith(bracketMatch: color);
    case VsCodeEditorField.widgetBorder:
      return e.copyWith(widgetBorder: color);
  }
}

/// Builds [QueryaTheme] from merged VS Code `colors` on top of [fallback].
QueryaTheme buildQueryaThemeFromVsCodeColors({
  required Brightness brightness,
  required Map<String, String> colors,
  QueryaTheme? fallback,
}) {
  final base = fallback ??
      (brightness == Brightness.light
          ? QueryaTheme.lightDefault
          : QueryaTheme.darkDefault);
  if (colors.isEmpty) return base;
  final manifest = VsCodeThemeManifest(
    type: brightness == Brightness.light ? 'light' : 'dark',
    colors: colors,
  );
  return buildQueryaThemeFromVsCodeManifest(manifest, fallback: base);
}
