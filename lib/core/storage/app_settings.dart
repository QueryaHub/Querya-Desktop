import 'dart:convert';

import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../theme/querya_theme_preset.dart';
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
}

/// Bumps [listenable] when any preference is persisted so open screens can reload.
abstract final class AppSettingsRevision {
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
    AppSettingsRevision.bump();
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
    AppSettingsRevision.bump();
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
    AppSettingsRevision.bump();
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
    AppSettingsRevision.bump();
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
    AppSettingsRevision.bump();
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
    final v =
        await LocalDb.instance.getAppSetting(AppSettingsKeys.themeOverridesJson);
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

  Future<void> clearThemeSettings() async {
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeMode);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themePreset);
    await LocalDb.instance.deleteAppSetting(AppSettingsKeys.themeOverridesJson);
    await deleteThemeImportKeys();
    AppSettingsRevision.bump();
  }
}
