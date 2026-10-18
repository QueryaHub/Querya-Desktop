import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Key-value app settings and the saved ER diagram layouts.
/// Part of [LocalDb], which keeps the same methods and delegates here.
class AppSettingsRepository {
  AppSettingsRepository(this._open);

  final Future<Database> Function() _open;

  Future<String?> getAppSetting(String key) async {
    final db = await _open();
    final rows = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> setAppSetting(String key, String value) async {
    final db = await _open();
    await db.rawInsert(
      'INSERT OR REPLACE INTO app_settings (key, value) VALUES (?, ?)',
      [key, value],
    );
  }

  Future<void> deleteAppSetting(String key) async {
    final db = await _open();
    await db.delete('app_settings', where: 'key = ?', whereArgs: [key]);
  }

  Future<String?> readErdLayout(int connectionId, String scope) async {
    final db = await _open();
    final rows = await db.query(
      'erd_layouts',
      columns: ['payload'],
      where: 'connection_id = ? AND scope = ?',
      whereArgs: [connectionId, scope],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first['payload'] as String?;
  }

  Future<void> writeErdLayout(
    int connectionId,
    String scope,
    String payload,
  ) async {
    final db = await _open();
    await db.rawInsert(
      'INSERT OR REPLACE INTO erd_layouts '
      '(connection_id, scope, payload, updated_at) VALUES (?, ?, ?, ?)',
      [connectionId, scope, payload, DateTime.now().toUtc().toIso8601String()],
    );
  }
}
