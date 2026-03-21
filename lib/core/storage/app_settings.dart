import 'local_db.dart';

/// Typed keys for [LocalDb] app_settings.
abstract final class AppSettingsKeys {
  static const postgresSqlStmtTimeoutSeconds =
      'postgres_sql_stmt_timeout_seconds';
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
  }
}
