import 'dart:convert';
import 'dart:ui';

import 'package:shadcn_flutter/shadcn_flutter.dart' show ColorScheme;
import 'package:querya_desktop/core/theme/parser/color_parser.dart';
import 'package:querya_desktop/core/theme/parser/querya_theme_manifest.dart';
import 'package:querya_desktop/core/theme/parser/vscode_theme_manifest.dart';
import 'package:querya_desktop/core/theme/querya_theme.dart';
import 'package:querya_desktop/core/theme/theme_metadata.dart';

/// One editable color in the theme editor MVP.
class ThemeEditorColorField {
  const ThemeEditorColorField({
    required this.section,
    required this.key,
    required this.label,
  });

  final String section;
  final String key;
  final String label;
}

/// MVP color fields for Preferences theme editor (TP-F3).
const themeEditorMvpColorFields = [
  ThemeEditorColorField(
    section: 'shadcn_colors',
    key: 'primary',
    label: 'Primary',
  ),
  ThemeEditorColorField(
    section: 'shadcn_colors',
    key: 'background',
    label: 'Background',
  ),
  ThemeEditorColorField(
    section: 'shadcn_colors',
    key: 'foreground',
    label: 'Foreground',
  ),
  ThemeEditorColorField(
    section: 'shadcn_colors',
    key: 'card',
    label: 'Card',
  ),
  ThemeEditorColorField(
    section: 'shadcn_colors',
    key: 'border',
    label: 'Border',
  ),
  ThemeEditorColorField(
    section: 'editor_colors',
    key: 'background',
    label: 'Editor background',
  ),
  ThemeEditorColorField(
    section: 'editor_colors',
    key: 'foreground',
    label: 'Editor foreground',
  ),
  ThemeEditorColorField(
    section: 'editor_colors',
    key: 'selection',
    label: 'Editor selection',
  ),
  ThemeEditorColorField(
    section: 'editor_colors',
    key: 'canvas',
    label: 'Workbench canvas',
  ),
  ThemeEditorColorField(
    section: 'editor_colors',
    key: 'sidebarBackground',
    label: 'Sidebar background',
  ),
];

/// Mutable draft for editing and exporting `querya.theme.v1`.
class ThemeEditorDraft {
  ThemeEditorDraft({
    required this.id,
    required this.name,
    required this.type,
    required Map<String, String> shadcnColors,
    required Map<String, String> editorColors,
    List<TokenColorRule> tokenColors = const [],
    this.description,
    this.author,
    this.version,
    this.homepage,
    this.license,
    this.preview,
    List<String> tags = const [],
    this.readOnlySource = false,
  })  : shadcnColors = Map<String, String>.from(shadcnColors),
        editorColors = Map<String, String>.from(editorColors),
        tokenColors = List<TokenColorRule>.from(tokenColors),
        tags = List<String>.from(tags);

  String id;
  String name;
  QueryaThemeType type;
  final Map<String, String> shadcnColors;
  final Map<String, String> editorColors;
  final List<TokenColorRule> tokenColors;
  String? description;
  String? author;
  String? version;
  String? homepage;
  String? license;
  String? preview;
  final List<String> tags;

  /// Built-in / asset themes are exported as copies only.
  final bool readOnlySource;

  factory ThemeEditorDraft.fromManifest(
    QueryaThemeManifest manifest, {
    bool readOnlySource = false,
  }) {
    return ThemeEditorDraft(
      id: manifest.id,
      name: manifest.name,
      type: manifest.type,
      shadcnColors: manifest.shadcnColors,
      editorColors: manifest.editorColors,
      tokenColors: manifest.tokenColors,
      description: manifest.description,
      author: manifest.author,
      version: manifest.version,
      homepage: manifest.homepage,
      license: manifest.license,
      preview: manifest.preview,
      tags: manifest.tags,
      readOnlySource: readOnlySource,
    );
  }

  factory ThemeEditorDraft.fromQueryaTheme({
    required String id,
    required String name,
    required bool isDark,
    required QueryaTheme theme,
    ThemeMetadata? metadata,
    bool readOnlySource = false,
  }) {
    final scheme = theme.colorScheme;
    final editor = theme.editor;
    final workbench = theme.workbench;

    return ThemeEditorDraft(
      id: id,
      name: name,
      type: isDark ? QueryaThemeType.dark : QueryaThemeType.light,
      shadcnColors: {
        for (final field in themeEditorMvpColorFields)
          if (field.section == 'shadcn_colors')
            field.key: _colorForShadcnField(field.key, scheme),
      },
      editorColors: {
        'background': formatVsCodeColor(editor.background),
        'foreground': formatVsCodeColor(editor.foreground),
        'selection': formatVsCodeColor(editor.selection),
        'canvas': formatVsCodeColor(workbench.canvas),
        'sidebarBackground': formatVsCodeColor(workbench.sidebarBackground),
      },
      tokenColors: theme.tokenColors,
      description: metadata?.description,
      author: metadata?.author,
      version: metadata?.version,
      homepage: metadata?.homepage,
      license: metadata?.license,
      preview: metadata?.preview,
      tags: metadata?.tags ?? const [],
      readOnlySource: readOnlySource,
    );
  }

  static String _colorForShadcnField(String key, ColorScheme scheme) {
    final color = switch (key) {
      'primary' => scheme.primary,
      'background' => scheme.background,
      'foreground' => scheme.foreground,
      'card' => scheme.card,
      'border' => scheme.border,
      _ => scheme.primary,
    };
    return formatVsCodeColor(color);
  }

  String? colorHex(ThemeEditorColorField field) {
    final map = field.section == 'shadcn_colors' ? shadcnColors : editorColors;
    return map[field.key];
  }

  void setColorHex(ThemeEditorColorField field, String hex) {
    final normalized = hex.trim();
    parseQueryaThemeColor(normalized);
    final map = field.section == 'shadcn_colors' ? shadcnColors : editorColors;
    map[field.key] = formatVsCodeColor(parseQueryaThemeColor(normalized));
  }

  void setColor(ThemeEditorColorField field, Color color) {
    final map = field.section == 'shadcn_colors' ? shadcnColors : editorColors;
    map[field.key] = formatVsCodeColor(color);
  }

  QueryaThemeManifest toManifest() {
    return QueryaThemeManifest(
      schema: queryaThemeSchemaV1,
      id: id,
      name: name,
      type: type,
      shadcnColors: Map.unmodifiable(shadcnColors),
      editorColors: Map.unmodifiable(editorColors),
      tokenColors: List.unmodifiable(tokenColors),
      description: description,
      author: author,
      version: version,
      homepage: homepage,
      license: license,
      preview: preview,
      tags: List.unmodifiable(tags),
    );
  }

  /// JSON export with a unique id when saving a built-in/read-only source.
  ThemeEditorDraft forExport({String? exportId}) {
    if (!readOnlySource && exportId == null) return this;
    final nextId = exportId ?? '$id-edited';
    return ThemeEditorDraft(
      id: nextId,
      name: '$name (edited)',
      type: type,
      shadcnColors: shadcnColors,
      editorColors: editorColors,
      tokenColors: tokenColors,
      description: description,
      author: author,
      version: version ?? '1.0.0',
      homepage: homepage,
      license: license,
      preview: preview,
      tags: tags,
      readOnlySource: false,
    );
  }

  String toExportJsonString() {
    return const JsonEncoder.withIndent('  ').convert(toManifest().toJson());
  }
}
