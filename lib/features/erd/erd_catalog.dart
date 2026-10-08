import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/erd/erd_model.dart';
import 'package:querya_desktop/features/workspace/sql_execution_delegate.dart';

/// Catalog queries per dialect. Column query yields `table, column, type,
/// isPk`; FK query yields `table, column, refTable, refColumn`.
///
/// Every output column has a distinct alias: the SQLite driver returns rows as
/// maps keyed by column name, so two `name` columns would collapse into one.
class ErdCatalog {
  ErdCatalog._();

  static String columnsSql(SqlDialect d) => switch (d) {
        SqlDialect.postgres => '''
SELECT c.table_name, c.column_name, c.data_type,
  CASE WHEN pk.column_name IS NULL THEN 0 ELSE 1 END
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  AND t.table_type = 'BASE TABLE'
LEFT JOIN (
  SELECT kcu.table_schema, kcu.table_name, kcu.column_name
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
    AND tc.table_schema = kcu.table_schema
  WHERE tc.constraint_type = 'PRIMARY KEY'
) pk ON pk.table_schema = c.table_schema AND pk.table_name = c.table_name
  AND pk.column_name = c.column_name
WHERE c.table_schema = current_schema()
ORDER BY c.table_name, c.ordinal_position''',
        SqlDialect.mysql => '''
SELECT c.table_name, c.column_name, c.column_type,
  IF(c.column_key = 'PRI', 1, 0)
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  AND t.table_type = 'BASE TABLE'
WHERE c.table_schema = DATABASE()
ORDER BY c.table_name, c.ordinal_position''',
        SqlDialect.sqlite => '''
SELECT m.name AS table_name, p.name AS column_name, p.type AS data_type,
  CASE WHEN p.pk > 0 THEN 1 ELSE 0 END AS is_pk
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, p.cid''',
      };

  static String foreignKeysSql(SqlDialect d) => switch (d) {
        SqlDialect.postgres => '''
SELECT kcu.table_name AS table_name, kcu.column_name AS column_name,
  ccu.table_name AS ref_table, ccu.column_name AS ref_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON ccu.constraint_name = tc.constraint_name
  AND ccu.table_schema = tc.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY' AND tc.table_schema = current_schema()''',
        SqlDialect.mysql => '''
SELECT table_name, column_name, referenced_table_name, referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE() AND referenced_table_name IS NOT NULL''',
        SqlDialect.sqlite => '''
SELECT m.name AS table_name, f."from" AS column_name,
  f."table" AS ref_table, f."to" AS ref_column
FROM sqlite_master m JOIN pragma_foreign_key_list(m.name) f
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
''',
      };

  /// Loads the schema of the current database through [delegate].
  static Future<ErdSchema> load(
    SqlExecutionDelegate delegate,
    SqlDialect dialect,
  ) async {
    final cols = await delegate.executeQuery(columnsSql(dialect));
    final fks = await delegate.executeQuery(foreignKeysSql(dialect));
    return ErdSchema.fromCatalog(columnRows: cols.rows, fkRows: fks.rows);
  }
}
