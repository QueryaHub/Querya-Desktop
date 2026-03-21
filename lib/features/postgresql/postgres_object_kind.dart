/// Kind of object selected in the PostgreSQL browser tree.
enum PostgresObjectKind {
  /// Base table (data grid).
  table,
  /// View (read-only grid).
  view,
  /// Materialized view (data + REFRESH MATERIALIZED VIEW).
  materializedView,
  /// Function or aggregate ([pg_get_functiondef]).
  function,
  /// Sequence (metadata + current value).
  sequence,
  /// All indexes in a schema (metadata list).
  schemaIndexes,
  /// All triggers in a schema.
  schemaTriggers,
  /// User-defined types in a schema.
  schemaTypes,
  /// [pg_extension] for current database.
  databaseExtensions,
  /// Foreign data wrappers and servers.
  databaseForeignData,
}
