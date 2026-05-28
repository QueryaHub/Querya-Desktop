import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'parser/color_parser.dart';
import 'parser/querya_theme_from_vscode.dart';
import 'parser/vscode_colors_merge.dart';
import 'querya_theme.dart';
import 'querya_theme_preset.dart';

/// Active theme state: preset, optional imported colors, user overrides.
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  QueryaThemePreset _preset = QueryaThemePreset.queryaDark;
  Map<String, String> _importedColors = const {};
  Map<String, String> _userOverrides = const {};
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  QueryaThemePreset get preset => _preset;

  bool get isLoaded => _loaded;

  /// User `workbench.colorCustomizations` layer (VS Code keys → hex).
  Map<String, String> get userColorOverrides =>
      Map.unmodifiable(_userOverrides);

  /// Imported theme `colors` layer (from file import; empty until wired).
  Map<String, String> get importedColors => Map.unmodifiable(_importedColors);

  /// Merged VS Code color keys: imported → user overrides.
  Map<String, String> get effectiveVsCodeColors => mergeVsCodeColorLayers([
        _importedColors,
        _userOverrides,
      ]);

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
    final preset = await AppSettings.instance.getThemePreset();
    final overrides = await AppSettings.instance.getThemeColorOverrides();
    _themeMode = mode;
    _preset = preset;
    _userOverrides = Map.unmodifiable(overrides);
    _loaded = true;
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    _preset = mode == ThemeMode.light
        ? QueryaThemePreset.queryaLight
        : QueryaThemePreset.queryaDark;
    await AppSettings.instance.setThemeMode(mode);
    await AppSettings.instance.setThemePreset(_preset);
    notifyListeners();
  }

  Future<void> setPreset(QueryaThemePreset preset) async {
    _preset = preset;
    _themeMode = preset == QueryaThemePreset.queryaLight
        ? ThemeMode.light
        : ThemeMode.dark;
    await AppSettings.instance.setThemePreset(preset);
    await AppSettings.instance.setThemeMode(_themeMode);
    notifyListeners();
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

  Future<void> resetToDefaults() async {
    await AppSettings.instance.clearThemeSettings();
    _themeMode = ThemeMode.dark;
    _preset = QueryaThemePreset.queryaDark;
    _importedColors = const {};
    _userOverrides = const {};
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
    if (merged.isEmpty) return fallback;
    return buildQueryaThemeFromVsCodeColors(
      brightness: brightness,
      colors: merged,
      fallback: fallback,
    );
  }
}
