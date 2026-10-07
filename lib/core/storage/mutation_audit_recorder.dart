import 'dart:async';

import 'package:querya_desktop/core/database/sql_mutation_classifier.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

/// Records an executed SQL script in the audit trail when it contains data or
/// schema changes (DML / DDL). Plain SELECTs are skipped. Fire and forget.
void auditSqlExecution({
  required ConnectionRow? connection,
  String? databaseName,
  required String sql,
  int? rowsAffected,
  required MutationAuditSource source,
}) {
  if (connection == null || !containsMutatingSql(sql)) return;
  unawaited(_record(
    connection: connection,
    databaseName: databaseName,
    sql: sql,
    rowsAffected: rowsAffected,
    source: source,
  ));
}

/// Records every statement of an applied staged-changes [plan].
///
/// The plan runs only after each statement matched a row (a statement that
/// matches nothing aborts the save), and every statement addresses one row by
/// primary key or inserts one, so each affected exactly one row.
void auditMutationPlan({
  required ConnectionRow? connection,
  String? databaseName,
  required TableMutationPlan plan,
  required MutationAuditSource source,
}) {
  if (connection == null) return;
  for (final statement in plan.statements) {
    unawaited(_record(
      connection: connection,
      databaseName: databaseName,
      sql: statement.sql,
      rowsAffected: 1,
      source: source,
    ));
  }
}

Future<void> _record({
  required ConnectionRow connection,
  required String? databaseName,
  required String sql,
  required int? rowsAffected,
  required MutationAuditSource source,
}) =>
    LocalDb.instance.recordMutationAudit(
      connectionId: connection.id,
      connectionName: connection.name,
      environment: connection.environment?.storageValue,
      databaseName: databaseName,
      sqlText: sql,
      rowsAffected: rowsAffected,
      source: source,
    );
