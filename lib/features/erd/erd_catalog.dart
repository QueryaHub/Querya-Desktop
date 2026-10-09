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
        // pg_catalog is readable by every role, unlike information_schema,
        // which hides keys of tables the current role has only SELECT on.
        SqlDialect.postgres => '''
SELECT c.relname AS table_name, a.attname AS column_name,
  format_type(a.atttypid, a.atttypmod) AS data_type,
  CASE WHEN pk.oid IS NULL THEN 0 ELSE 1 END AS is_pk
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_constraint pk
  ON pk.conrelid = c.oid AND pk.contype = 'p' AND a.attnum = ANY (pk.conkey)
WHERE n.nspname = current_schema()
  AND c.relkind IN ('r', 'p')
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY c.relname, a.attnum''',
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
        // conkey and confkey are paired by position, so a composite key yields
        // one row per column pair. References outside the current schema are
        // skipped: their table names would otherwise match same-named tables.
        SqlDialect.postgres => '''
SELECT src.relname AS table_name, sa.attname AS column_name,
  ref.relname AS ref_table, ra.attname AS ref_column
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
JOIN pg_catalog.pg_namespace n ON n.oid = src.relnamespace
JOIN pg_catalog.pg_class ref ON ref.oid = con.confrelid
JOIN pg_catalog.pg_namespace rn ON rn.oid = ref.relnamespace
CROSS JOIN LATERAL unnest(con.conkey, con.confkey) AS k(src_attnum, ref_attnum)
JOIN pg_catalog.pg_attribute sa
  ON sa.attrelid = con.conrelid AND sa.attnum = k.src_attnum
JOIN pg_catalog.pg_attribute ra
  ON ra.attrelid = con.confrelid AND ra.attnum = k.ref_attnum
WHERE con.contype = 'f'
  AND n.nspname = current_schema() AND rn.nspname = current_schema()''',
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
