import 'package:flutter/material.dart' as material;
import 'package:querya_desktop/core/storage/app_settings.dart';
import 'package:querya_desktop/core/theme/querya_material_theme.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'parser/apply_token_colors_to_editor.dart';
import 'parser/color_parser.dart';
import 'parser/querya_theme_from_manifest.dart';
import 'parser/querya_theme_from_vscode.dart';
import 'parser/querya_theme_manifest.dart';
import 'parser/vscode_colors_merge.dart';
import 'parser/vscode_theme_manifest.dart';
import 'querya_theme.dart';
import 'querya_theme_preset.dart';
import 'theme_definition.dart';
import 'theme_folder_watcher.dart';
import 'theme_import_service.dart';
import 'theme_load_result.dart';
import 'theme_paths.dart';
import 'theme_registry_service.dart';
import 'theme_remote_install_service.dart';
import '../extensions/extension_paths.dart';

/// Active theme state: preset, optional imported colors, user overrides.
class ThemeController extends ChangeNotifier {
  static const String builtinQueryaDarkId = 'querya-dark';
  static const String builtinQueryaLightId = 'querya-light';

  /// Shown in Preferences when persisted registry selection cannot be restored.
  static const String selectedThemeStartupFallbackMessage =
      'Selected theme failed to load. Using Querya Dark.';

  static const ThemeDefinition builtinQueryaDarkDefinition = ThemeDefinition(
    id: builtinQueryaDarkId,
    name: 'Querya Dark',
    source: ThemeSource.builtin,
    format: ThemeFormat.queryaCustom,
    isDark: true,
  );

  static const ThemeDefinition builtinQueryaLightDefinition = ThemeDefinition(
    id: builtinQueryaLightId,
    name: 'Querya Light',
    source: ThemeSource.builtin,
    format: ThemeFormat.queryaCustom,
    isDark: false,
  );

  static const List<ThemeDefinition> _builtinThemeDefinitions = [
    builtinQueryaDarkDefinition,
    builtinQueryaLightDefinition,
  ];

  ThemeRegistryService _registryService;

  ThemeController._({ThemeRegistryService? registryService})
      : _registryService = registryService ?? ThemeRegistryService();

  static final ThemeController instance = ThemeController._();

  ThemeMode _themeMode = ThemeMode.dark;
  QueryaThemePreset _preset = QueryaThemePreset.queryaDark;
  Map<String, String> _importedColors = const {};
  List<TokenColorRule> _importedTokenColors = const [];
  Map<String, String> _userOverrides = const {};
  String? _importedThemeName;
  bool _loaded = false;
  bool _themeAnimationEnabled = false;

  List<ThemeDefinition> _availableThemes = const [];
  String? _selectedThemeId;
  String? _selectedThemePath;
  String? _selectedThemeLoadError;
  QueryaTheme? _registryTheme;
  bool _registrySelectionFailed = false;
  bool _isLoadingAvailableThemes = false;
  ThemeFolderWatcher? _themeFolderWatcher;
  bool _editorPreviewActive = false;
  String? _editorPreviewRestoreThemeId;

  QueryaTheme? _cachedLightTheme;
  QueryaTheme? _cachedDarkTheme;
  QueryaTheme? _cachedActiveTheme;
  ThemeData? _cachedLightShadcnTheme;
  ThemeData? _cachedDarkShadcnTheme;
  material.ThemeData? _cachedMaterialTheme;
  ColorScheme? _cachedMaterialThemeScheme;

  ThemeMode get themeMode => _themeMode;

  /// When true, [QueryaApp] enables ShadcnAnimatedTheme transitions.
  bool get themeAnimationEnabled => _themeAnimationEnabled;

  QueryaThemePreset get preset => _preset;

  bool get isLoaded => _loaded;

  bool get hasImportedTheme => _importedColors.isNotEmpty;

  String? get importedThemeName => _importedThemeName;

  List<ThemeDefinition> get availableThemes =>
      List.unmodifiable(_availableThemes);

  /// True while [loadAvailableThemes] is scanning the registry.
  bool get isLoadingAvailableThemes => _isLoadingAvailableThemes;

  String? get selectedThemeId => _selectedThemeId;

  String? get selectedThemePath => _selectedThemePath;

  String? get selectedThemeLoadError => _selectedThemeLoadError;

  /// Theme id for registry-backed selection, or built-in/legacy preset ids.
  String get effectiveSelectedThemeId {
    if (_selectedThemeId != null) return _selectedThemeId!;
    return switch (_preset) {
      QueryaThemePreset.queryaLight => builtinQueryaLightId,
      QueryaThemePreset.imported => ThemeImportService.legacyImportedThemeId,
      _ => builtinQueryaDarkId,
    };
  }

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
  QueryaTheme get activeTheme =>
      _resolvedThemeForBrightness(_effectiveBrightness());

  ThemeData get lightShadcnTheme => _cachedLightShadcnTheme ??=
      _resolvedThemeForBrightness(Brightness.light).toShadcnThemeData();

  ThemeData get darkShadcnTheme => _cachedDarkShadcnTheme ??=
      _resolvedThemeForBrightness(Brightness.dark).toShadcnThemeData();

  /// Cached Material theme for dialogs/dropdowns (avoids rebuild churn).
  material.ThemeData materialThemeFor(ColorScheme scheme) {
    if (_cachedMaterialTheme != null && _cachedMaterialThemeScheme == scheme) {
      return _cachedMaterialTheme!;
    }
    _cachedMaterialThemeScheme = scheme;
    return _cachedMaterialTheme = materialThemeFromQuerya(scheme);
  }

  @visibleForTesting
  void setRegistryServiceForTest(ThemeRegistryService service) {
    _registryService = service;
  }

  @visibleForTesting
  ThemeRegistryService get registryServiceForTest => _registryService;

  @visibleForTesting
  bool get isThemeFolderWatcherStarted =>
      _themeFolderWatcher?.isStarted ?? false;

  @visibleForTesting
  bool get isEditorPreviewActive => _editorPreviewActive;

  /// Applies [manifest] for live editor preview without persisting selection.
  Future<void> previewEditorManifest(QueryaThemeManifest manifest) async {
    if (!_editorPreviewActive) {
      _editorPreviewRestoreThemeId = effectiveSelectedThemeId;
      _editorPreviewActive = true;
    }

    _registryTheme = queryaThemeFromManifest(manifest);
    _registrySelectionFailed = false;
    _selectedThemeLoadError = null;
    _themeMode = manifest.isLight ? ThemeMode.light : ThemeMode.dark;
    _notifyThemeChanged();
  }

  /// Restores the theme that was active before editor preview.
  Future<void> endEditorPreview() async {
    if (!_editorPreviewActive) return;

    final restoreId = _editorPreviewRestoreThemeId;
    _editorPreviewActive = false;
    _editorPreviewRestoreThemeId = null;

    if (restoreId != null) {
      await setThemeById(restoreId);
    } else {
      _notifyThemeChanged();
    }
  }

  /// Watches extensions directory and debounces [loadAvailableThemes].
  Future<void> startThemeFolderWatcher() async {
    _themeFolderWatcher ??= ThemeFolderWatcher(
      themesDirectory: ExtensionPaths.extensionsDirectory,
      onThemesChanged: loadAvailableThemes,
    );
    await _themeFolderWatcher!.start();
  }

  /// Stops the themes folder watcher (used in tests and app teardown).
  Future<void> stopThemeFolderWatcher() async {
    await _themeFolderWatcher?.stop();
  }

  void _invalidateThemeCache() {
    _cachedLightTheme = null;
    _cachedDarkTheme = null;
    _cachedActiveTheme = null;
    _cachedLightShadcnTheme = null;
    _cachedDarkShadcnTheme = null;
    _cachedMaterialTheme = null;
    _cachedMaterialThemeScheme = null;
  }

  void _notifyThemeChanged() {
    _invalidateThemeCache();
    notifyListeners();
  }

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

    _availableThemes = _mergeBuiltinThemes(
      await _registryService.loadThemeDefinitions(),
    );
    await _restoreSelectedRegistryTheme();
    await startThemeFolderWatcher();

    _loaded = true;
    _notifyThemeChanged();
  }

  Future<void> loadAvailableThemes() async {
    if (_isLoadingAvailableThemes) return;

    _isLoadingAvailableThemes = true;
    notifyListeners();

    try {
      final scanned = await _registryService.loadThemeDefinitions();
      _availableThemes = _mergeBuiltinThemes(scanned);
      _syncSelectedThemeAfterRefresh();
    } on Object {
      // Registry scan skips broken files per entry; keep the prior list on failure.
    } finally {
      _isLoadingAvailableThemes = false;
      notifyListeners();
    }
  }

  void _syncSelectedThemeAfterRefresh() {
    final selectedId = _selectedThemeId;
    if (selectedId == null) return;

    final stillAvailable = _definitionById(
      selectedId,
      path: _selectedThemePath,
    );
    if (stillAvailable == null) {
      if (_registryTheme != null) {
        // Keep the in-memory active theme; only the on-disk scan lost the file.
        _selectedThemeLoadError = selectedThemeStartupFallbackMessage;
        return;
      }
      _markRegistrySelectionFailed();
      return;
    }

    if (_registryTheme != null) {
      _selectedThemeLoadError = null;
      _registrySelectionFailed = false;
    }
  }

  void _markRegistrySelectionFailed() {
    _registryTheme = null;
    _registrySelectionFailed = true;
    _selectedThemeLoadError = selectedThemeStartupFallbackMessage;
  }

  Future<void> setThemeById(String id) async {
    if (id == builtinQueryaDarkId) {
      await _applyBuiltinPreset(QueryaThemePreset.queryaDark);
      return;
    }
    if (id == builtinQueryaLightId) {
      await _applyBuiltinPreset(QueryaThemePreset.queryaLight);
      return;
    }

    final definition = _definitionById(id);
    if (definition == null) {
      _selectedThemeLoadError = 'Theme "$id" not found.';
      notifyListeners();
      return;
    }

    final result = await _registryService.loadTheme(definition);
    switch (result) {
      case ThemeLoadSuccess(:final theme, :final definition):
        _registryTheme = theme;
        _registrySelectionFailed = false;
        _selectedThemeId = definition.id;
        _selectedThemePath = definition.path;
        _selectedThemeLoadError = null;
        _themeMode = theme.brightness == Brightness.light
            ? ThemeMode.light
            : ThemeMode.dark;
        await AppSettings.instance.setSelectedThemeId(definition.id);
        await AppSettings.instance
            .setSelectedThemeSource(definition.source.name);
        await AppSettings.instance.setSelectedThemePath(definition.path);
        await AppSettings.instance.setThemeMode(_themeMode);
        _notifyThemeChanged();
      case ThemeLoadFailure(:final message):
        _selectedThemeLoadError = message;
        notifyListeners();
    }
  }

  Future<ThemeLoadResult> previewThemeById(String id) async {
    if (id == builtinQueryaDarkId) {
      return const ThemeLoadSuccess(
        definition: builtinQueryaDarkDefinition,
        theme: QueryaTheme.darkDefault,
      );
    }
    if (id == builtinQueryaLightId) {
      return const ThemeLoadSuccess(
        definition: builtinQueryaLightDefinition,
        theme: QueryaTheme.lightDefault,
      );
    }

    final definition = _definitionById(id);
    if (definition == null) {
      return ThemeLoadFailure(
        definition: ThemeDefinition(
          id: id,
          name: id,
          source: ThemeSource.builtin,
          format: ThemeFormat.queryaCustom,
          isDark: true,
        ),
        message: 'Theme "$id" not found.',
      );
    }
    return _registryService.loadTheme(definition);
  }

  Future<void> setThemeAnimationEnabled(bool enabled) async {
    _themeAnimationEnabled = enabled;
    await AppSettings.instance.setThemeAnimationEnabled(enabled);
    _notifyThemeChanged();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    if (_registryTheme == null && _preset != QueryaThemePreset.imported) {
      _preset = mode == ThemeMode.light
          ? QueryaThemePreset.queryaLight
          : QueryaThemePreset.queryaDark;
      await AppSettings.instance.setThemePreset(_preset);
    }
    await AppSettings.instance.setThemeMode(mode);
    _notifyThemeChanged();
  }

  Future<void> setPreset(QueryaThemePreset preset) async {
    if (preset == QueryaThemePreset.imported && !hasImportedTheme) {
      return;
    }
    await _clearRegistrySelection();
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
    _notifyThemeChanged();
  }

  /// Copies a theme into the user themes directory and activates it.
  Future<ThemeDefinitionImportResult> importRegistryThemeFile(
    String path,
  ) async {
    final result = await _registryService.importThemeFile(path);
    return _applyRegistryImportResult(result);
  }

  /// Downloads a theme from [url] and activates it when import succeeds.
  Future<ThemeDefinitionImportResult> importRegistryThemeFromUrl(
    String url, {
    String? sha256Checksum,
    ThemeRemoteInstallService? remoteInstallService,
  }) async {
    final installer =
        remoteInstallService ?? ThemeRemoteInstallService(_registryService);
    final result = await installer.installFromUrl(
      url,
      sha256Checksum: sha256Checksum,
    );
    return _applyRegistryImportResult(result);
  }

  Future<ThemeDefinitionImportResult> _applyRegistryImportResult(
    ThemeDefinitionImportResult result,
  ) async {
    switch (result) {
      case ThemeDefinitionImportSuccess(:final definition):
        _availableThemes = _mergeBuiltinThemes(
          await _registryService.loadThemeDefinitions(),
        );
        await setThemeById(definition.id);
      case ThemeDefinitionImportFailure():
        notifyListeners();
    }
    return result;
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
        await _clearRegistrySelection();
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
        _availableThemes = _mergeBuiltinThemes(
          await _registryService.loadThemeDefinitions(),
        );
        _notifyThemeChanged();
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
    _notifyThemeChanged();
  }

  /// Removes only the user override layer (keeps preset/imported theme).
  Future<void> clearColorOverrides() async {
    _userOverrides = const {};
    await AppSettings.instance.clearThemeColorOverrides();
    _notifyThemeChanged();
  }

  /// Clears imported theme file and settings; falls back to Querya Dark.
  Future<void> clearImportedTheme() async {
    await ThemeImportService.deletePersistedImport();
    await AppSettings.instance.clearThemeImport();
    _importedColors = const {};
    _importedTokenColors = const [];
    _importedThemeName = null;
    if (_preset == QueryaThemePreset.imported) {
      await _clearRegistrySelection();
      _preset = QueryaThemePreset.queryaDark;
      _themeMode = ThemeMode.dark;
      await AppSettings.instance.setThemePreset(_preset);
      await AppSettings.instance.setThemeMode(_themeMode);
    }
    _availableThemes = _mergeBuiltinThemes(
      await _registryService.loadThemeDefinitions(),
    );
    _notifyThemeChanged();
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
    _availableThemes = _mergeBuiltinThemes(
      await _registryService.loadThemeDefinitions(),
    );
    _selectedThemeId = null;
    _selectedThemePath = null;
    _selectedThemeLoadError = null;
    _registryTheme = null;
    _registrySelectionFailed = false;
    _notifyThemeChanged();
  }

  Future<void> _restoreSelectedRegistryTheme() async {
    _selectedThemeId = await AppSettings.instance.getSelectedThemeId();
    _selectedThemePath = await AppSettings.instance.getSelectedThemePath();
    final selectedSource = await AppSettings.instance.getSelectedThemeSource();
    _selectedThemeLoadError = null;
    _registryTheme = null;
    _registrySelectionFailed = false;

    if (_selectedThemeId == null) return;

    final definition = _definitionById(
      _selectedThemeId!,
      source: selectedSource,
      path: _selectedThemePath,
    );
    if (definition == null) {
      _markRegistrySelectionFailed();
      return;
    }

    final result = await _registryService.loadTheme(definition);
    switch (result) {
      case ThemeLoadSuccess(:final theme, :final definition):
        _registryTheme = theme;
        _selectedThemeId = definition.id;
        _selectedThemePath = definition.path;
        _registrySelectionFailed = false;
        _selectedThemeLoadError = null;
        _themeMode = theme.brightness == Brightness.light
            ? ThemeMode.light
            : ThemeMode.dark;
      case ThemeLoadFailure():
        _markRegistrySelectionFailed();
    }
  }

  Future<void> _clearRegistrySelection() async {
    _registryTheme = null;
    _registrySelectionFailed = false;
    _selectedThemeId = null;
    _selectedThemePath = null;
    _selectedThemeLoadError = null;
    await AppSettings.instance.clearSelectedThemeRegistry();
  }

  Future<void> _applyBuiltinPreset(QueryaThemePreset preset) async {
    await _clearRegistrySelection();
    _preset = preset;
    _themeMode = preset == QueryaThemePreset.queryaLight
        ? ThemeMode.light
        : ThemeMode.dark;
    await AppSettings.instance.setThemePreset(preset);
    await AppSettings.instance.setThemeMode(_themeMode);
    _notifyThemeChanged();
  }

  List<ThemeDefinition> _mergeBuiltinThemes(List<ThemeDefinition> scanned) {
    final merged = <ThemeDefinition>[..._builtinThemeDefinitions];
    for (final definition in scanned) {
      if (!_builtinThemeDefinitions
          .any((builtin) => builtin.id == definition.id)) {
        merged.add(definition);
      }
    }
    merged.sort(
      (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
    return List.unmodifiable(merged);
  }

  ThemeDefinition? _definitionById(
    String id, {
    String? source,
    String? path,
  }) {
    final matches = _availableThemes.where((definition) => definition.id == id);
    if (matches.isEmpty) return null;

    if (source != null && source.isNotEmpty) {
      final bySource =
          matches.where((definition) => definition.source.name == source);
      if (bySource.isNotEmpty) return bySource.first;
    }
    if (path != null && path.isNotEmpty) {
      final byPath = matches.where((definition) => definition.path == path);
      if (byPath.isNotEmpty) return byPath.first;
    }
    return matches.first;
  }

  QueryaTheme _resolvedThemeForBrightness(Brightness brightness) {
    if (_registryTheme != null) return _registryTheme!;
    if (_registrySelectionFailed && _selectedThemeId != null) {
      return QueryaTheme.darkDefault;
    }
    if (brightness == Brightness.light) {
      return _cachedLightTheme ??= _themeForBrightness(Brightness.light);
    }
    if (brightness == Brightness.dark) {
      return _cachedDarkTheme ??= _themeForBrightness(Brightness.dark);
    }
    return _cachedActiveTheme ??= _themeForBrightness(brightness);
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
