import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../motion/querya_motion_scope.dart';
import '../theme/querya_theme_preset.dart';
import '../updater/update_manifest.dart';
import 'local_db.dart';

/// Default cap on rows shown in SQL workspace result grids (full result may be larger).
const int kDefaultSqlResultMaxRows = 5000;

/// Allowed values for [AppSettings.getSqlResultMaxRows] (nearest preset is used).
const List<int> kSqlResultMaxRowsPresets = [
  1000,
  2500,
  5000,
  10000,
  25000,
  50000,
  100000,
];

/// Default monospace size in the SQL editor (logical pixels).
const double kDefaultSqlEditorFontSize = 13;

/// Default interface scale (1.0 = 100%).
const double kDefaultUiScale = 1.0;

/// Minimum interface scale (Telegram Desktop supports 75%).
const double kMinUiScale = 0.75;

/// Maximum interface scale (Telegram goes to 300%; 200% is enough for Querya).
const double kMaxUiScale = 2.0;

/// Slider step — 1% increments when Shift is held (fine control).
const double kUiScaleStep = 0.01;

/// Fixed tick marks on the interface scale slider (75% … 200%).
const List<double> kUiScalePresets = [
  0.75,
  0.85,
  0.9,
  1.0,
  1.1,
  1.25,
  1.5,
  1.75,
  2.0,
];

int nearestUiScalePresetIndex(double scale) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < kUiScalePresets.length; i++) {
    final dist = (kUiScalePresets[i] - scale).abs();
    if (dist < bestDist) {
      bestDist = dist;
      best = i;
    }
  }
  return best;
}

double snapUiScaleToPreset(double scale) =>
    kUiScalePresets[nearestUiScalePresetIndex(scale)];

double _normalizeUiScaleContinuous(double value) {
  final clamped = value.clamp(kMinUiScale, kMaxUiScale);
  final steps = ((clamped - kMinUiScale) / kUiScaleStep).round();
  return (kMinUiScale + steps * kUiScaleStep).clamp(kMinUiScale, kMaxUiScale);
}

double _normalizeUiScale(double value, {bool fine = false}) =>
    fine ? _normalizeUiScaleContinuous(value) : snapUiScaleToPreset(value);

/// Default cap on stored SQL history entries per connection + database.
const int kDefaultSqlHistoryMaxEntries = 100;

/// Allowed values for [AppSettings.getSqlHistoryMaxEntries] (nearest preset is used).
const List<int> kSqlHistoryMaxEntriesPresets = [25, 50, 100, 200, 500];

int _normalizeSqlHistoryMaxEntries(int n) {
  final c = n.clamp(25, 500);
  return kSqlHistoryMaxEntriesPresets.reduce(
    (a, b) => (c - a).abs() <= (c - b).abs() ? a : b,
  );
}

int _normalizeSqlResultMaxRows(int n) {
  final c = n.clamp(100, 100000);
  return kSqlResultMaxRowsPresets.reduce(
    (a, b) => (c - a).abs() <= (c - b).abs() ? a : b,
  );
}

/// Typed keys for [LocalDb] app_settings.
abstract final class AppSettingsKeys {
  static const postgresSqlStmtTimeoutSeconds =
      'postgres_sql_stmt_timeout_seconds';
  static const mysqlSqlStmtTimeoutSeconds = 'mysql_sql_stmt_timeout_seconds';
  static const sqlResultMaxRows = 'sql_result_max_rows';
  static const sqlEditorFontSizePoints = 'sql_editor_font_size_points';
  static const sqlHistoryMaxEntries = 'sql_history_max_entries';
  static const themeMode = 'theme_mode';
  static const themePreset = 'theme_preset';
  static const themeOverridesJson = 'theme_overrides_json';
  static const themeImportPath = 'theme_import_path';
  static const themeImportName = 'theme_import_name';
  static const themeImportedColorsJson = 'theme_imported_colors_json';
  static const themeSelectedId = 'theme_selected_id';
  static const themeSelectedSource = 'theme_selected_source';
  static const themeSelectedPath = 'theme_selected_path';
  static const themeAnimationEnabled = 'theme_animation_enabled';
  static const uiScale = 'ui_scale';
  static const motionLevel = 'motion_level';
  static const updateChannel = 'update_channel';
  static const checkForUpdatesOnStartup = 'check_for_updates_on_startup';
  static const updateDismissedVersion = 'update_dismissed_version';
}

/// Bumps [listenable] when any preference is persisted (theme, legacy listeners).
abstract final class AppSettingsRevision {
  static final ValueNotifier<int> listenable = ValueNotifier(0);

  static void bump() => listenable.value++;
}

/// Bumps when SQL workspace preferences change (timeouts, grid, editor font, history).
abstract final class SqlWorkspaceSettingsRevision {
  static final ValueNotifier<int> listenable = ValueNotifier(0);

  static void bump() => listenable.value++;
}

/// User preferences backed by [LocalDb] (SQLite).
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  /// `null` = use driver / URI default.
  Future<int?> getPostgresSqlStmtTimeoutSeconds() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.postgresSqlStmtTimeoutSeconds,
    );
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v);
  }

  Future<void> setPostgresSqlStmtTimeoutSeconds(int? seconds) async {
    if (seconds == null) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.postgresSqlStmtTimeoutSeconds,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.postgresSqlStmtTimeoutSeconds,
        seconds.toString(),
      );
    }
    SqlWorkspaceSettingsRevision.bump();
  }

  /// `null` = use driver default for statement duration.
  Future<int?> getMysqlSqlStmtTimeoutSeconds() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.mysqlSqlStmtTimeoutSeconds,
    );
    if (v == null || v.isEmpty) return null;
    return int.tryParse(v);
  }

  Future<void> setMysqlSqlStmtTimeoutSeconds(int? seconds) async {
    if (seconds == null) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.mysqlSqlStmtTimeoutSeconds,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.mysqlSqlStmtTimeoutSeconds,
        seconds.toString(),
      );
    }
    SqlWorkspaceSettingsRevision.bump();
  }

  /// Max rows loaded into the result grid for PostgreSQL / MySQL workspaces.
  Future<int> getSqlResultMaxRows() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.sqlResultMaxRows,
    );
    if (v == null || v.isEmpty) return kDefaultSqlResultMaxRows;
    final n = int.tryParse(v);
    if (n == null) return kDefaultSqlResultMaxRows;
    return _normalizeSqlResultMaxRows(n);
  }

  Future<void> setSqlResultMaxRows(int rows) async {
    final preset = kSqlResultMaxRowsPresets.contains(rows)
        ? rows
        : _normalizeSqlResultMaxRows(rows);
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.sqlResultMaxRows,
      preset.toString(),
    );
    SqlWorkspaceSettingsRevision.bump();
  }

  /// Editor font size in logical pixels.
  Future<double> getSqlEditorFontSize() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.sqlEditorFontSizePoints,
    );
    if (v == null || v.isEmpty) return kDefaultSqlEditorFontSize;
    final n = int.tryParse(v);
    if (n == null) return kDefaultSqlEditorFontSize;
    return n.clamp(10, 24).toDouble();
  }

  Future<void> setSqlEditorFontSize(double sizePoints) async {
    final clamped = sizePoints.round().clamp(10, 24);
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.sqlEditorFontSizePoints,
      clamped.toString(),
    );
    SqlWorkspaceSettingsRevision.bump();
  }

  /// Global interface scale for typography and compact controls.
  Future<double> getUiScale() async {
    final v = await LocalDb.instance.getAppSetting(AppSettingsKeys.uiScale);
    if (v == null || v.isEmpty) return kDefaultUiScale;
    final n = double.tryParse(v);
    if (n == null) return kDefaultUiScale;
    return _normalizeUiScaleContinuous(n);
  }

  Future<void> setUiScale(double scale, {bool fine = false}) async {
    final normalized = _normalizeUiScale(scale, fine: fine);
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.uiScale,
      normalized.toStringAsFixed(2),
    );
  }

  /// Max SQL history rows kept per connection + database (oldest trimmed).
  Future<int> getSqlHistoryMaxEntries() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.sqlHistoryMaxEntries,
    );
    if (v == null || v.isEmpty) return kDefaultSqlHistoryMaxEntries;
    final n = int.tryParse(v);
    if (n == null) return kDefaultSqlHistoryMaxEntries;
    return _normalizeSqlHistoryMaxEntries(n);
  }

  Future<void> setSqlHistoryMaxEntries(int entries) async {
    final preset = kSqlHistoryMaxEntriesPresets.contains(entries)
        ? entries
        : _normalizeSqlHistoryMaxEntries(entries);
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.sqlHistoryMaxEntries,
      preset.toString(),
    );
    SqlWorkspaceSettingsRevision.bump();
  }

  /// UI theme mode (dark / light / system).
  Future<ThemeMode> getThemeMode() async {
    final v = await LocalDb.instance.getAppSetting(AppSettingsKeys.themeMode);
    return switch (v) {
      'light' => ThemeMode.light,
      'system' => ThemeMode.system,
      _ => ThemeMode.dark,
    };
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final stored = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    };
    await LocalDb.instance.setAppSetting(AppSettingsKeys.themeMode, stored);
    AppSettingsRevision.bump();
  }

  Future<QueryaThemePreset> getThemePreset() async {
    final v = await LocalDb.instance.getAppSetting(AppSettingsKeys.themePreset);
    return switch (v) {
      'querya_light' => QueryaThemePreset.queryaLight,
      'imported' => QueryaThemePreset.imported,
      _ => QueryaThemePreset.queryaDark,
    };
  }

  Future<void> setThemePreset(QueryaThemePreset preset) async {
    final stored = switch (preset) {
      QueryaThemePreset.queryaLight => 'querya_light',
      QueryaThemePreset.imported => 'imported',
      QueryaThemePreset.queryaDark => 'querya_dark',
    };
    await LocalDb.instance.setAppSetting(AppSettingsKeys.themePreset, stored);
    AppSettingsRevision.bump();
  }

  Future<String?> getThemeImportName() async {
    return LocalDb.instance.getAppSetting(AppSettingsKeys.themeImportName);
  }

  Future<void> setThemeImportName(String? name) async {
    if (name == null || name.isEmpty) {
      await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportName);
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeImportName,
        name,
      );
    }
    AppSettingsRevision.bump();
  }

  Future<String?> getThemeImportPath() async {
    return LocalDb.instance.getAppSetting(AppSettingsKeys.themeImportPath);
  }

  Future<void> setThemeImportPath(String? path) async {
    if (path == null || path.isEmpty) {
      await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportPath);
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeImportPath,
        path,
      );
    }
    AppSettingsRevision.bump();
  }

  Future<String?> getSelectedThemeId() async {
    final v =
        await LocalDb.instance.getAppSetting(AppSettingsKeys.themeSelectedId);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setSelectedThemeId(String? id) async {
    if (id == null || id.isEmpty) {
      await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeSelectedId);
    } else {
      await LocalDb.instance.setAppSetting(AppSettingsKeys.themeSelectedId, id);
    }
    AppSettingsRevision.bump();
  }

  Future<String?> getSelectedThemeSource() async {
    final v = await LocalDb.instance
        .getAppSetting(AppSettingsKeys.themeSelectedSource);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setSelectedThemeSource(String? source) async {
    if (source == null || source.isEmpty) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.themeSelectedSource,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeSelectedSource,
        source,
      );
    }
    AppSettingsRevision.bump();
  }

  Future<String?> getSelectedThemePath() async {
    final v =
        await LocalDb.instance.getAppSetting(AppSettingsKeys.themeSelectedPath);
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setSelectedThemePath(String? path) async {
    if (path == null || path.isEmpty) {
      await LocalDb.instance
          .deleteAppSetting(AppSettingsKeys.themeSelectedPath);
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeSelectedPath,
        path,
      );
    }
    AppSettingsRevision.bump();
  }

  Future<void> clearSelectedThemeRegistry() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeSelectedId);
    await LocalDb.instance
        .deleteAppSetting(AppSettingsKeys.themeSelectedSource);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeSelectedPath);
    AppSettingsRevision.bump();
  }

  Future<Map<String, String>> getThemeImportedColors() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.themeImportedColorsJson,
    );
    if (v == null || v.isEmpty) return {};
    try {
      final decoded = jsonDecode(v);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key != null &&
            key.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          out[key] = value;
        }
      }
      return out;
    } on FormatException {
      return {};
    }
  }

  Future<void> setThemeImportedColors(Map<String, String> colors) async {
    if (colors.isEmpty) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.themeImportedColorsJson,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeImportedColorsJson,
        jsonEncode(colors),
      );
    }
    AppSettingsRevision.bump();
  }

  Future<void> clearThemeImport() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportPath);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportName);
    await LocalDb.instance.deleteAppSetting(
      AppSettingsKeys.themeImportedColorsJson,
    );
    AppSettingsRevision.bump();
  }

  /// Clears import metadata without bumping (for batched clears).
  Future<void> deleteThemeImportKeys() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportPath);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeImportName);
    await LocalDb.instance.deleteAppSetting(
      AppSettingsKeys.themeImportedColorsJson,
    );
  }

  Future<Map<String, String>> getThemeColorOverrides() async {
    final v = await LocalDb.instance
        .getAppSetting(AppSettingsKeys.themeOverridesJson);
    if (v == null || v.isEmpty) return {};
    try {
      final decoded = jsonDecode(v);
      if (decoded is! Map) return {};
      final out = <String, String>{};
      for (final entry in decoded.entries) {
        final key = entry.key?.toString();
        final value = entry.value?.toString();
        if (key != null &&
            key.isNotEmpty &&
            value != null &&
            value.isNotEmpty) {
          out[key] = value;
        }
      }
      return out;
    } on FormatException {
      return {};
    }
  }

  Future<void> setThemeColorOverrides(Map<String, String> overrides) async {
    if (overrides.isEmpty) {
      await clearThemeColorOverrides();
      return;
    }
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.themeOverridesJson,
      jsonEncode(overrides),
    );
    AppSettingsRevision.bump();
  }

  Future<void> clearThemeColorOverrides() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeOverridesJson);
    AppSettingsRevision.bump();
  }

  /// Smooth color transitions when switching theme (off by default).
  Future<bool> getThemeAnimationEnabled() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.themeAnimationEnabled,
    );
    if (v == null || v.isEmpty) return false;
    return v == 'true' || v == '1';
  }

  Future<void> setThemeAnimationEnabled(bool enabled) async {
    if (!enabled) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.themeAnimationEnabled,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.themeAnimationEnabled,
        'true',
      );
    }
    AppSettingsRevision.bump();
  }

  Future<void> clearThemeSettings() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeMode);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themePreset);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeOverridesJson);
    await LocalDb.instance
        .deleteAppSetting(AppSettingsKeys.themeAnimationEnabled);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeSelectedId);
    await LocalDb.instance
        .deleteAppSetting(AppSettingsKeys.themeSelectedSource);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeSelectedPath);
    await deleteThemeImportKeys();
    AppSettingsRevision.bump();
  }

  Future<QueryaMotionLevel> getMotionLevel() async {
    final v = await LocalDb.instance.getAppSetting(AppSettingsKeys.motionLevel);
    return switch (v) {
      'off' => QueryaMotionLevel.off,
      'reduced' => QueryaMotionLevel.reduced,
      _ => QueryaMotionLevel.full,
    };
  }

  Future<void> setMotionLevel(QueryaMotionLevel level) async {
    final stored = switch (level) {
      QueryaMotionLevel.off => 'off',
      QueryaMotionLevel.reduced => 'reduced',
      QueryaMotionLevel.full => 'full',
    };
    await LocalDb.instance.setAppSetting(AppSettingsKeys.motionLevel, stored);
    AppSettingsRevision.bump();
  }

  /// Update distribution channel (`stable` hides pre-releases).
  Future<UpdateChannel> getUpdateChannel() async {
    final v =
        await LocalDb.instance.getAppSetting(AppSettingsKeys.updateChannel);
    return switch (v) {
      'dev' => UpdateChannel.dev,
      _ => UpdateChannel.stable,
    };
  }

  Future<void> setUpdateChannel(UpdateChannel channel) async {
    final stored = switch (channel) {
      UpdateChannel.dev => 'dev',
      UpdateChannel.stable => 'stable',
    };
    await LocalDb.instance.setAppSetting(AppSettingsKeys.updateChannel, stored);
    AppSettingsRevision.bump();
  }

  /// Whether to poll GitHub Releases silently when the app starts.
  Future<bool> getCheckForUpdatesOnStartup() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.checkForUpdatesOnStartup,
    );
    if (v == null || v.isEmpty) return true;
    return v == 'true' || v == '1';
  }

  Future<void> setCheckForUpdatesOnStartup(bool enabled) async {
    await LocalDb.instance.setAppSetting(
      AppSettingsKeys.checkForUpdatesOnStartup,
      enabled ? 'true' : 'false',
    );
    AppSettingsRevision.bump();
  }

  /// Version the user dismissed via "Remind me later" (badge hidden until newer).
  Future<String?> getUpdateDismissedVersion() async {
    final v = await LocalDb.instance.getAppSetting(
      AppSettingsKeys.updateDismissedVersion,
    );
    if (v == null || v.isEmpty) return null;
    return v;
  }

  Future<void> setUpdateDismissedVersion(String? version) async {
    if (version == null || version.isEmpty) {
      await LocalDb.instance.deleteAppSetting(
        AppSettingsKeys.updateDismissedVersion,
      );
    } else {
      await LocalDb.instance.setAppSetting(
        AppSettingsKeys.updateDismissedVersion,
        version,
      );
    }
    AppSettingsRevision.bump();
  }
}
