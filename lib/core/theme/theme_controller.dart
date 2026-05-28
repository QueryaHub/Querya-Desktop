import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'querya_theme.dart';
import 'querya_theme_preset.dart';

/// Active theme state: preset + [ThemeMode], persisted via [AppSettings].
class ThemeController extends ChangeNotifier {
  ThemeController._();

  static final ThemeController instance = ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  QueryaThemePreset _preset = QueryaThemePreset.queryaDark;
  bool _loaded = false;

  ThemeMode get themeMode => _themeMode;

  QueryaThemePreset get preset => _preset;

  bool get isLoaded => _loaded;

  /// Workbench + editor tokens for the current preset/mode.
  QueryaTheme get activeTheme {
    if (_themeMode == ThemeMode.system) {
      final b = WidgetsBinding.instance.platformDispatcher.platformBrightness;
      return b == Brightness.dark
          ? QueryaTheme.darkDefault
          : QueryaTheme.lightDefault;
    }
    return _preset == QueryaThemePreset.queryaLight
        ? QueryaTheme.lightDefault
        : QueryaTheme.darkDefault;
  }

  ThemeData get lightShadcnTheme =>
      QueryaTheme.lightDefault.toShadcnThemeData();

  ThemeData get darkShadcnTheme => QueryaTheme.darkDefault.toShadcnThemeData();

  Future<void> load() async {
    final mode = await AppSettings.instance.getThemeMode();
    final preset = await AppSettings.instance.getThemePreset();
    _themeMode = mode;
    _preset = preset;
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

  Future<void> resetToDefaults() async {
    await AppSettings.instance.clearThemeSettings();
    _themeMode = ThemeMode.dark;
    _preset = QueryaThemePreset.queryaDark;
    notifyListeners();
  }
}
