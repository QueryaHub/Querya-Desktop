import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/storage/local_db.dart';
import 'package:querya_desktop/features/postgresql/postgres_browser_views.dart';
import 'package:querya_desktop/features/postgresql/postgres_object_kind.dart';
import 'package:querya_desktop/features/postgresql/postgres_routine_view.dart';
import 'package:querya_desktop/features/postgresql/postgres_sequence_view.dart';
import 'package:querya_desktop/features/postgresql/postgres_table_view.dart';

/// Workspace content for a single PostgreSQL tree object (grid, routine, lists).
Widget buildPostgresObjectWorkspace({
  required ConnectionRow connection,
  required ({String database, String schema, String name, PostgresObjectKind kind}) pg,
}) {
  switch (pg.kind) {
    case PostgresObjectKind.table:
      return PostgresTableView(
        key: ValueKey(
          'pg_table_${connection.id}_${pg.schema}_${pg.name}_${pg.kind}',
        ),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
        tableName: pg.name,
        isView: false,
        isMaterializedView: false,
      );
    case PostgresObjectKind.view:
      return PostgresTableView(
        key: ValueKey(
          'pg_table_${connection.id}_${pg.schema}_${pg.name}_${pg.kind}',
        ),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
        tableName: pg.name,
        isView: true,
        isMaterializedView: false,
      );
    case PostgresObjectKind.materializedView:
      return PostgresTableView(
        key: ValueKey(
          'pg_mat_${connection.id}_${pg.schema}_${pg.name}_${pg.kind}',
        ),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
        tableName: pg.name,
        isView: false,
        isMaterializedView: true,
      );
    case PostgresObjectKind.function:
      return PostgresRoutineView(
        key: ValueKey('pg_fn_${connection.id}_${pg.schema}_${pg.name}'),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
        routineName: pg.name,
      );
    case PostgresObjectKind.sequence:
      return PostgresSequenceView(
        key: ValueKey('pg_seq_${connection.id}_${pg.schema}_${pg.name}'),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
        sequenceName: pg.name,
      );
    case PostgresObjectKind.schemaIndexes:
      return PostgresIndexListView(
        key: ValueKey('pg_idx_${connection.id}_${pg.schema}'),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
      );
    case PostgresObjectKind.schemaTriggers:
      return PostgresTriggerListView(
        key: ValueKey('pg_trg_${connection.id}_${pg.schema}'),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
      );
    case PostgresObjectKind.schemaTypes:
      return PostgresTypeListView(
        key: ValueKey('pg_typ_${connection.id}_${pg.schema}'),
        connectionRow: connection,
        database: pg.database,
        schema: pg.schema,
      );
    case PostgresObjectKind.databaseExtensions:
      return PostgresExtensionListView(
        key: ValueKey('pg_ext_${connection.id}_${pg.database}'),
        connectionRow: connection,
        database: pg.database,
      );
    case PostgresObjectKind.databaseForeignData:
      return PostgresFdwListView(
        key: ValueKey('pg_fdw_${connection.id}_${pg.database}'),
        connectionRow: connection,
        database: pg.database,
      );
  }
}
