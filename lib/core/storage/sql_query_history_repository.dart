import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';

/// The SQL history of each connection and database, capped per bucket.
/// Part of [LocalDb], which keeps the same methods and delegates here.
class SqlQueryHistoryRepository {
  SqlQueryHistoryRepository(this._open);

  final Future<Database> Function() _open;

  /// Inserts per history bucket since the last prune, so a prune runs every few
  /// inserts and not on each one.
  final Map<String, int> _historyInsertCounts = {};

  /// Forgets the insert counts of a removed connection.
  void forgetConnection(int connectionId) => _historyInsertCounts
      .removeWhere((k, _) => k.startsWith('$connectionId::'));

  Future<void> recordSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    required String sqlText,
    int maxEntries = kDefaultSqlHistoryCap,
    bool forcePrune = false,
  }) async {
    final sql = sqlText.trim();
    if (sql.isEmpty) return;
    if (maxEntries < 1) return;
    final db = await _open();
    final dbKey = normalizeHistoryDatabaseName(databaseName);
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('sql_query_history', {
      'connection_id': connectionId,
      'database_name': dbKey,
      'sql_text': sql,
      'recorded_at': now,
    });

    final bucketKey = '$connectionId::${dbKey ?? ''}';
    final insertCount = (_historyInsertCounts[bucketKey] ?? 0) + 1;
    _historyInsertCounts[bucketKey] = insertCount;

    final batchThreshold = maxEntries <= 10 ? 1 : 10;
    if (forcePrune || insertCount >= batchThreshold) {
      _historyInsertCounts[bucketKey] = 0;
      await _pruneSqlQueryHistoryBucket(
        db,
        connectionId: connectionId,
        databaseName: dbKey,
        maxEntries: maxEntries,
      );
    }
  }

  /// Keeps the newest [maxEntries] rows in a (connection, database) bucket.
  ///
  /// Selects overflow ids (oldest first), then deletes by primary key — avoids
  /// nested `DELETE … SELECT … OFFSET` plans as history grows.
  Future<void> _pruneSqlQueryHistoryBucket(
    Database db, {
    required int connectionId,
    required String? databaseName,
    required int maxEntries,
  }) async {
    final countRows = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ''',
      [connectionId, databaseName],
    );
    final count = sqliteInt(countRows.first['c']) ?? 0;
    final excess = count - maxEntries;
    if (excess <= 0) return;

    final overflow = await db.rawQuery(
      '''
      SELECT id FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ORDER BY id ASC
      LIMIT ?
      ''',
      [connectionId, databaseName, excess],
    );
    if (overflow.isEmpty) return;

    final ids = <Object>[];
    for (final row in overflow) {
      final id = row['id'];
      if (id != null) ids.add(id);
    }
    if (ids.isEmpty) return;

    final placeholders = List.filled(ids.length, '?').join(',');
    await db.rawDelete(
      'DELETE FROM sql_query_history WHERE id IN ($placeholders)',
      ids,
    );
  }

  Future<List<SqlQueryHistoryEntry>> listSqlQueryHistory({
    required int connectionId,
    String? databaseName,
    int limit = 50,
  }) async {
    final db = await _open();
    final dbKey = normalizeHistoryDatabaseName(databaseName);
    final rows = await db.rawQuery(
      '''
      SELECT id, connection_id, database_name, sql_text, recorded_at
      FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ORDER BY id DESC
      LIMIT ?
      ''',
      [connectionId, dbKey, limit],
    );
    return rows.map(SqlQueryHistoryEntry.fromMap).toList();
  }

  /// Removes all history rows for [connectionId] (every database bucket).
  Future<void> clearSqlQueryHistoryForConnection(int connectionId) async {
    _historyInsertCounts.removeWhere((k, _) => k.startsWith('$connectionId::'));
    final db = await _open();
    await db.delete(
      'sql_query_history',
      where: 'connection_id = ?',
      whereArgs: [connectionId],
    );
  }

  /// Removes history for [connectionId] and [databaseName] only (same bucket as [listSqlQueryHistory]).
  Future<void> clearSqlQueryHistoryBucket({
    required int connectionId,
    String? databaseName,
  }) async {
    final dbKey = normalizeHistoryDatabaseName(databaseName);
    _historyInsertCounts.remove('$connectionId::${dbKey ?? ''}');
    final db = await _open();
    await db.rawDelete(
      '''
      DELETE FROM sql_query_history
      WHERE connection_id = ? AND database_name IS NOT DISTINCT FROM ?
      ''',
      [connectionId, dbKey],
    );
  }
}
