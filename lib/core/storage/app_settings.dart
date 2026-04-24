import 'package:flutter/foundation.dart';

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
}
