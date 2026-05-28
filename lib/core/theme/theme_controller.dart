import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'parser/apply_token_colors_to_editor.dart';
import 'parser/color_parser.dart';
import 'parser/querya_theme_from_vscode.dart';
import 'parser/vscode_colors_merge.dart';
import 'parser/vscode_theme_manifest.dart';
import 'querya_theme.dart';
import 'querya_theme_preset.dart';
import 'theme_import_service.dart';

/// Active theme state: preset, optional imported colors, user overrides.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  QueryaThemePreset _preset = QueryaThemePreset.queryaDark;
  Map<String, String> _importedColors = const {};
  List<TokenColorRule> _importedTokenColors = const [];
  Map<String, String> _userOverrides = const {};
  String? _importedThemeName;
  bool _loaded = false;
  bool _themeAnimationEnabled = false;

  ThemeMode get themeMode => _themeMode;

  /// When true, [QueryaApp] enables ShadcnAnimatedTheme transitions.
  bool get themeAnimationEnabled => _themeAnimationEnabled;

  QueryaThemePreset get preset => _preset;

  bool get isLoaded => _loaded;

  bool get hasImportedTheme => _importedColors.isNotEmpty;

  String? get importedThemeName => _importedThemeName;

  /// User `workbench.colorCustomizations` layer (VS Code keys → hex).
  Map<String, String> get userColorOverrides =>
      Map.unmodifiable(_userOverrides);

  /// Imported theme `colors` layer (from file import).
  Map<String, String> get importedColors => Map.unmodifiable(_importedColors);

  /// Merged VS Code color keys for the active preset.
  Map<String, String> get effectiveVsCodeColors {
    if (_preset == QueryaThemePreset.imported) {
      return mergeVsCodeColorLayers([
        _importedColors,
        _userOverrides,
      ]);
    }
    return mergeVsCodeColorLayers([_userOverrides]);
  }

  /// Parsed effective colors for supported VS Code keys only.
  Map<String, Color> get effectiveWorkbenchColors {
    final out = <String, Color>{};
    for (final entry in effectiveVsCodeColors.entries) {
      try {
        out[entry.key] = parseVsCodeColor(entry.value);
      } on FormatException {
        continue;
      }
    }
    return Map.unmodifiable(out);
  }

  /// Workbench + editor tokens for the current preset/mode and overrides.
  QueryaTheme get activeTheme => _themeForBrightness(_effectiveBrightness());

  ThemeData get lightShadcnTheme =>
      _themeForBrightness(Brightness.light).toShadcnThemeData();

  ThemeData get darkShadcnTheme =>
      _themeForBrightness(Brightness.dark).toShadcnThemeData();

  Future<void> load() async {
    final mode = await AppSettings.instance.getThemeMode();
    var preset = await AppSettings.instance.getThemePreset();
    final overrides = await AppSettings.instance.getThemeColorOverrides();
    var imported = await AppSettings.instance.getThemeImportedColors();
    _importedThemeName = await AppSettings.instance.getThemeImportName();

    if (imported.isEmpty) {
      final fromDisk = await ThemeImportService.loadPersistedColors();
      if (fromDisk != null && fromDisk.isNotEmpty) {
        imported = fromDisk;
        await AppSettings.instance.setThemeImportedColors(imported);
      }
    }
    _importedTokenColors = await ThemeImportService.loadPersistedTokenColors();

    if (preset == QueryaThemePreset.imported && imported.isEmpty) {
      preset = QueryaThemePreset.queryaDark;
      await AppSettings.instance.setThemePreset(preset);
    }

    _themeMode = mode;
    _preset = preset;
    _userOverrides = Map.unmodifiable(overrides);
    _importedColors = Map.unmodifiable(imported);
    _themeAnimationEnabled =
        await AppSettings.instance.getThemeAnimationEnabled();
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeAnimationEnabled(bool enabled) async {
    _themeAnimationEnabled = enabled;
    await AppSettings.instance.setThemeAnimationEnabled(enabled);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    if (_preset != QueryaThemePreset.imported) {
      _preset = mode == ThemeMode.light
          ? QueryaThemePreset.queryaLight
          : QueryaThemePreset.queryaDark;
      await AppSettings.instance.setThemePreset(_preset);
    }
    await AppSettings.instance.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setPreset(QueryaThemePreset preset) async {
    if (preset == QueryaThemePreset.imported && !hasImportedTheme) {
      return;
    }
    _preset = preset;
    if (preset == QueryaThemePreset.imported) {
      await AppSettings.instance.setThemePreset(preset);
    } else {
      _themeMode = preset == QueryaThemePreset.queryaLight
          ? ThemeMode.light
          : ThemeMode.dark;
      await AppSettings.instance.setThemePreset(preset);
      await AppSettings.instance.setThemeMode(_themeMode);
    }
    notifyListeners();
  }

  /// Parses a VS Code theme file, persists it, and activates the imported preset.
  Future<ThemeImportResult> importThemeFromFile(String path) async {
    final result = await ThemeImportService.importFromPath(path);
    switch (result) {
      case ThemeImportSuccess(
          :final name,
          :final isDark,
          :final colors,
          :final tokenColors,
          :final storedPath,
        ):
        _importedColors = Map.unmodifiable(colors);
        _importedTokenColors = List.unmodifiable(tokenColors);
        _importedThemeName = name;
        _preset = QueryaThemePreset.imported;
        _themeMode = isDark ? ThemeMode.dark : ThemeMode.light;
        await AppSettings.instance.setThemeImportedColors(colors);
        await AppSettings.instance.setThemeImportName(name);
        await AppSettings.instance.setThemeImportPath(storedPath);
        await AppSettings.instance.setThemePreset(QueryaThemePreset.imported);
        await AppSettings.instance.setThemeMode(_themeMode);
        notifyListeners();
        return result;
      case ThemeImportFailure():
        return result;
    }
  }

  /// Sets or clears a user override for a VS Code `colors` key.
  Future<void> setWorkbenchColor(String vscodeKey, Color? value) async {
    final next = Map<String, String>.from(_userOverrides);
    if (value == null) {
      next.remove(vscodeKey);
    } else {
      next[vscodeKey] = formatVsCodeColor(value);
    }
    _userOverrides = Map.unmodifiable(next);
    await AppSettings.instance.setThemeColorOverrides(next);
    notifyListeners();
  }

  /// Removes only the user override layer (keeps preset/imported theme).
  Future<void> clearColorOverrides() async {
    _userOverrides = const {};
    await AppSettings.instance.clearThemeColorOverrides();
    notifyListeners();
  }

  /// Clears imported theme file and settings; falls back to Querya Dark.
  Future<void> clearImportedTheme() async {
    await ThemeImportService.deletePersistedImport();
    await AppSettings.instance.clearThemeImport();
    _importedColors = const {};
    _importedTokenColors = const [];
    _importedThemeName = null;
    if (_preset == QueryaThemePreset.imported) {
      _preset = QueryaThemePreset.queryaDark;
      _themeMode = ThemeMode.dark;
      await AppSettings.instance.setThemePreset(_preset);
      await AppSettings.instance.setThemeMode(_themeMode);
    }
    notifyListeners();
  }

  Future<void> resetToDefaults() async {
    await ThemeImportService.deletePersistedImport();
    await AppSettings.instance.clearThemeSettings();
    _themeMode = ThemeMode.dark;
    _preset = QueryaThemePreset.queryaDark;
    _importedColors = const {};
    _importedTokenColors = const [];
    _userOverrides = const {};
    _importedThemeName = null;
    _themeAnimationEnabled = false;
    notifyListeners();
  }

  Brightness _effectiveBrightness() {
    if (_themeMode == ThemeMode.system) {
      final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return b;
    }
    return _themeMode == ThemeMode.light ? Brightness.light : Brightness.dark;
  }

  QueryaTheme _themeForBrightness(Brightness brightness) {
    final fallback = brightness == Brightness.light
        ? QueryaTheme.lightDefault
        : QueryaTheme.darkDefault;
    final merged = effectiveVsCodeColors;
    if (merged.isEmpty && _importedTokenColors.isEmpty) return fallback;

    var theme = merged.isEmpty
        ? fallback
        : buildQueryaThemeFromVsCodeColors(
            brightness: brightness,
            colors: merged,
            fallback: fallback,
          );

    if (_importedTokenColors.isNotEmpty) {
      theme = theme.copyWith(
        tokenColors: _importedTokenColors,
        editor: applyTokenColorsToEditor(theme.editor, _importedTokenColors),
      );
    }
    return theme;
  }
}
