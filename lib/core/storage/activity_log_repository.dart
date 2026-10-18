import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:querya_desktop/core/storage/local_db_models.dart';

/// The local audit trails: executed data / schema changes and MCP tool calls.
/// Part of [LocalDb], which keeps the same methods and delegates here.
class ActivityLogRepository {
  ActivityLogRepository(this._open);

  final Future<Database> Function() _open;

  var _mutationAuditInsertCount = 0;

  /// Appends one executed mutation to the audit trail and trims the table to
  /// [kMutationAuditCap] rows. Never throws: auditing must not break a query.
  Future<void> recordMutationAudit({
    int? connectionId,
    required String connectionName,
    String? environment,
    String? databaseName,
    required String sqlText,
    int? rowsAffected,
    required MutationAuditSource source,
  }) async {
    final sql = sqlText.trim();
    if (sql.isEmpty) return;
    try {
      final db = await _open();
      await db.insert('mutation_audit', {
        'connection_id': connectionId,
        'connection_name': connectionName,
        'environment': environment,
        'database_name': normalizeHistoryDatabaseName(databaseName),
        'sql_text': sql,
        'rows_affected': rowsAffected,
        'source': source.storageValue,
        'recorded_at': DateTime.now().toUtc().toIso8601String(),
      });
      _mutationAuditInsertCount++;
      if (_mutationAuditInsertCount >= 50) {
        _mutationAuditInsertCount = 0;
        await db.rawDelete(
          'DELETE FROM mutation_audit WHERE id <= ('
          'SELECT id FROM mutation_audit ORDER BY id DESC LIMIT 1 OFFSET ?)',
          [kMutationAuditCap],
        );
      }
    } catch (e) {
      // Best effort, but a missing audit trail should not be invisible.
      debugPrint('LocalDb: could not record a mutation audit entry: $e');
    }
  }

  /// Newest-first audit entries, optionally for one connection.
  Future<List<MutationAuditEntry>> listMutationAudit({
    int? connectionId,
    int limit = 200,
  }) async {
    final db = await _open();
    final rows = await db.query(
      'mutation_audit',
      where: connectionId == null ? null : 'connection_id = ?',
      whereArgs: connectionId == null ? null : [connectionId],
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(MutationAuditEntry.fromMap).toList();
  }

  Future<void> clearMutationAudit() async {
    final db = await _open();
    await db.delete('mutation_audit');
    _mutationAuditInsertCount = 0;
  }

  /// Appends one MCP tool call and keeps the newest [kMcpActivityCap].
  /// Never throws: logging must not break a tool call.
  Future<void> recordMcpActivity(McpActivityEntry entry) async {
    try {
      final db = await _open();
      final map = entry.toMap()..remove('id');
      await db.insert('mcp_activity', map);
      await db.rawDelete(
        'DELETE FROM mcp_activity WHERE id <= ('
        'SELECT id FROM mcp_activity ORDER BY id DESC LIMIT 1 OFFSET ?)',
        [kMcpActivityCap],
      );
    } catch (e) {
      debugPrint('LocalDb: could not record MCP activity: $e');
    }
  }

  /// Newest-first MCP tool calls.
  Future<List<McpActivityEntry>> listMcpActivity({int limit = 200}) async {
    final db = await _open();
    final rows =
        await db.query('mcp_activity', orderBy: 'id DESC', limit: limit);
    return rows.map(McpActivityEntry.fromMap).toList();
  }

  Future<void> clearMcpActivity() async {
    final db = await _open();
    await db.delete('mcp_activity');
  }
}
