/// Kind of object selected in the PostgreSQL browser tree.
enum PostgresObjectKind {
  /// Base table (data grid).
  table,
  /// View (read-only grid).
  view,
  /// Function or aggregate ([pg_get_functiondef]).
  function,
  /// Sequence (metadata + current value).
  sequence,
}
