import 'dart:io';
import 'dart:ui' show Brightness;
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/theme_controller.dart';
import 'package:querya_desktop/core/theme/theme_definition.dart';
import 'package:querya_desktop/core/theme/theme_editor_draft.dart';

/// Builds a [ThemeEditorDraft] from the active theme selection.
abstract final class ThemeEditorLoader {
  static Future<ThemeEditorDraft> fromController(ThemeController controller) async {
    final selectedId = controller.effectiveSelectedThemeId;
    final definition = _definitionForId(controller, selectedId);
    final readOnlySource = definition?.source == ThemeSource.builtin;

    final manifest = await _loadSourceManifest(definition);
    if (manifest != null) {
      return ThemeEditorDraft.fromManifest(
        manifest,
        readOnlySource: readOnlySource,
      );
    }

    return ThemeEditorDraft.fromQueryaTheme(
      id: selectedId,
      name: definition?.name ?? selectedId,
      isDark: controller.activeTheme.brightness == Brightness.dark,
      theme: controller.activeTheme,
      metadata: definition?.metadata,
      readOnlySource: readOnlySource,
    );
  }

  static ThemeDefinition? _definitionForId(
    ThemeController controller,
    String id,
  ) {
    for (final definition in controller.availableThemes) {
      if (definition.id == id) return definition;
    }
    return null;
  }

  static Future<QueryaThemeManifest?> _loadSourceManifest(
    ThemeDefinition? definition,
  ) async {
    if (definition == null ||
        definition.format != ThemeFormat.queryaCustom ||
        definition.path == null ||
        definition.source == ThemeSource.builtin) {
      return null;
    }

    final file = File(definition.path!);
    if (!await file.exists()) return null;

    try {
      return QueryaThemeManifest.fromJsonString(await file.readAsString());
    } on Object {
      return null;
    }
  }
}
