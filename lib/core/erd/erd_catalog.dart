import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_table_names.dart';
import 'package:querya_desktop/core/database/sql_query_runner.dart';

/// Catalog queries per dialect. Column query yields `table, column, type,
/// isPk, isNullable`; FK query yields `table, column, refTable, refColumn`.
///
/// Tables outside the current schema (PostgreSQL) are named `schema.table`,
/// so relations between schemas keep the same keys as the rest of the diagram.
///
/// Every output column has a distinct alias: the SQLite driver returns rows as
/// maps keyed by column name, so two `name` columns would collapse into one.
class ErdCatalog {
  ErdCatalog._();

  /// Most catalog rows read for a diagram or MCP. Larger catalogs are cut and
  /// reported as truncated, rather than dropped silently.
  static const int catalogRowLimit = 200000;

  /// PostgreSQL name of relation alias [rel] in namespace alias [ns]:
  /// `table` for the current schema, `schema.table` otherwise.
  static String _pgQualified(String rel, String ns) =>
      "CASE WHEN $ns.nspname = current_schema() THEN $rel.relname "
      "ELSE $ns.nspname || '.' || $rel.relname END";

  /// Columns of [schema] (PostgreSQL) or of the connected database. [schema]
  /// `null` means the current schema.
  static String columnsSql(SqlDialect d, {String? schema}) => switch (d) {
        // pg_catalog is readable by every role, unlike information_schema,
        // which hides keys of tables the current role has only SELECT on.
        SqlDialect.postgres => '''
SELECT ${_pgQualified('c', 'ns')} AS table_name, a.attname AS column_name,
  format_type(a.atttypid, a.atttypmod) AS data_type,
  CASE WHEN pk.oid IS NULL THEN 0 ELSE 1 END AS is_pk,
  CASE WHEN a.attnotnull THEN 0 ELSE 1 END AS is_nullable
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
LEFT JOIN pg_catalog.pg_constraint pk
  ON pk.conrelid = c.oid AND pk.contype = 'p' AND a.attnum = ANY (pk.conkey)
WHERE ns.nspname = ${schema == null ? 'current_schema()' : "'${_lit(schema)}'"}
  AND c.relkind IN ('r', 'p')
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY table_name, a.attnum''',
        SqlDialect.mysql => '''
SELECT c.table_name, c.column_name, c.column_type,
  IF(c.column_key = 'PRI', 1, 0),
  IF(c.is_nullable = 'YES', 1, 0)
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  AND t.table_type = 'BASE TABLE'
WHERE c.table_schema = DATABASE()
ORDER BY c.table_name, c.ordinal_position''',
        SqlDialect.sqlite => '''
SELECT m.name AS table_name, p.name AS column_name, p.type AS data_type,
  CASE WHEN p.pk > 0 THEN 1 ELSE 0 END AS is_pk,
  CASE WHEN p."notnull" = 0 THEN 1 ELSE 0 END AS is_nullable
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type = 'table' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, p.cid''',
      };

  /// Columns of the views (and PostgreSQL materialized views) of the current
  /// schema or database, in the shape of [columnsSql]: no primary key, every
  /// column nullable. MCP lists them next to the tables.
  static String viewColumnsSql(SqlDialect d) => switch (d) {
        SqlDialect.postgres => '''
SELECT ${_pgQualified('c', 'ns')} AS table_name, a.attname AS column_name,
  format_type(a.atttypid, a.atttypmod) AS data_type,
  0 AS is_pk, 1 AS is_nullable
FROM pg_catalog.pg_attribute a
JOIN pg_catalog.pg_class c ON c.oid = a.attrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid = c.relnamespace
WHERE ns.nspname = current_schema()
  AND c.relkind IN ('v', 'm')
  AND a.attnum > 0 AND NOT a.attisdropped
ORDER BY table_name, a.attnum''',
        SqlDialect.mysql => '''
SELECT c.table_name, c.column_name, c.column_type, 0, 1
FROM information_schema.columns c
JOIN information_schema.tables t
  ON t.table_schema = c.table_schema AND t.table_name = c.table_name
  AND t.table_type = 'VIEW'
WHERE c.table_schema = DATABASE()
ORDER BY c.table_name, c.ordinal_position''',
        SqlDialect.sqlite => '''
SELECT m.name AS table_name, p.name AS column_name, p.type AS data_type,
  0 AS is_pk, 1 AS is_nullable
FROM sqlite_master m JOIN pragma_table_info(m.name) p
WHERE m.type = 'view' AND m.name NOT LIKE 'sqlite_%'
ORDER BY m.name, p.cid''',
      };

  /// Foreign keys of every user schema. A reference across schemas is named
  /// `schema.table` on the side that lives outside the current schema.
  static String foreignKeysSql(SqlDialect d) => switch (d) {
        // conkey and confkey are paired by position, so a composite key yields
        // one row per column pair.
        SqlDialect.postgres => '''
SELECT ${_pgQualified('src', 'ns')} AS table_name, sa.attname AS column_name,
  ${_pgQualified('ref', 'rn')} AS ref_table, ra.attname AS ref_column
FROM pg_catalog.pg_constraint con
JOIN pg_catalog.pg_class src ON src.oid = con.conrelid
JOIN pg_catalog.pg_namespace ns ON ns.oid = src.relnamespace
JOIN pg_catalog.pg_class ref ON ref.oid = con.confrelid
JOIN pg_catalog.pg_namespace rn ON rn.oid = ref.relnamespace
CROSS JOIN LATERAL unnest(con.conkey, con.confkey) AS k(src_attnum, ref_attnum)
JOIN pg_catalog.pg_attribute sa
  ON sa.attrelid = con.conrelid AND sa.attnum = k.src_attnum
JOIN pg_catalog.pg_attribute ra
  ON ra.attrelid = con.confrelid AND ra.attnum = k.ref_attnum
WHERE con.contype = 'f'
  AND ns.nspname NOT IN ('pg_catalog', 'information_schema')
  AND ns.nspname NOT LIKE 'pg_toast%'
  AND rn.nspname NOT IN ('pg_catalog', 'information_schema')''',
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

  static String _lit(String s) => s.replaceAll("'", "''");

  /// Schema part of a diagram name: `sales` for `sales.orders`, `null` for a
  /// table of the current schema.
  static String? schemaOf(String name) {
    final dot = name.indexOf('.');
    return dot < 0 ? null : name.substring(0, dot);
  }

  /// Loads the schema of the current database through [delegate].
  static Future<ErdSchema> load(
    SqlQueryRunner delegate,
    SqlDialect dialect,
  ) async {
    final cols = await delegate.executeQuery(
      columnsSql(dialect),
      limit: catalogRowLimit,
    );
    final fks = await delegate.executeQuery(
      foreignKeysSql(dialect),
      limit: catalogRowLimit,
    );
    return ErdSchema.fromCatalog(
      columnRows: cols.rows,
      fkRows: fks.rows,
      truncated: cols.isTruncated || fks.isTruncated,
    );
  }

  /// Tables within [depth] foreign keys of [table] in either direction, with
  /// their columns. Cycles and self references end the walk.
  static Future<ErdSchema> loadNeighbourhood(
    SqlQueryRunner delegate,
    SqlDialect dialect, {
    required String table,
    int depth = 1,
  }) async {
    final fksResult = await delegate.executeQuery(
      foreignKeysSql(dialect),
      limit: catalogRowLimit,
    );
    final fks = fksResult.rows;
    var truncated = fksResult.isTruncated;
    // The table browser names a PostgreSQL table `schema.table`, while the
    // catalog names one of the current schema `table`. Use the catalog's name.
    final (_, bare) = ErdTableNames.split(table, dialect);
    var focus = table;
    if (bare != table && !_mentions(fks, table) && _mentions(fks, bare)) {
      focus = bare;
    }
    var names = neighbourhood(fks, focus, depth);

    final fetched = <List<String>>[];
    final schemas = {for (final n in names) schemaOf(n)};
    for (final s in schemas) {
      final rows = await delegate.executeQuery(
        columnsSql(dialect, schema: dialect == SqlDialect.postgres ? s : null),
        limit: catalogRowLimit,
      );
      truncated = truncated || rows.isTruncated;
      fetched.addAll(rows.rows.where((r) => r.isNotEmpty));
    }
    var cols = [for (final r in fetched) if (names.contains(r[0])) r];
    // A table with no keys either way: only its columns show which name the
    // catalog uses.
    if (bare != focus &&
        !cols.any((r) => r[0] == focus) &&
        fetched.any((r) => r[0] == bare)) {
      focus = bare;
      names = neighbourhood(fks, focus, depth);
      cols = [for (final r in fetched) if (names.contains(r[0])) r];
    }
    return ErdSchema.fromCatalog(
      columnRows: cols,
      fkRows: [
        for (final r in fks)
          if (r.length >= 4 && names.contains(r[0]) && names.contains(r[2])) r,
      ],
      truncated: truncated,
    );
  }

  /// Whether a foreign key row names [table] on either side.
  static bool _mentions(List<List<String>> fkRows, String table) => fkRows
      .any((r) => r.length >= 4 && (r[0] == table || r[2] == table));

  /// Names of the tables within [depth] foreign keys of [table], including
  /// [table] itself. Pure, for tests.
  static Set<String> neighbourhood(
    List<List<String>> fkRows,
    String table,
    int depth,
  ) {
    final adjacent = <String, Set<String>>{};
    for (final r in fkRows) {
      if (r.length < 4) continue;
      adjacent.putIfAbsent(r[0], () => {}).add(r[2]);
      adjacent.putIfAbsent(r[2], () => {}).add(r[0]);
    }
    final seen = {table};
    var frontier = {table};
    for (var i = 0; i < depth && frontier.isNotEmpty; i++) {
      final next = <String>{};
      for (final t in frontier) {
        for (final n in adjacent[t] ?? const <String>{}) {
          if (seen.add(n)) next.add(n);
        }
      }
      frontier = next;
    }
    return seen;
  }
}
