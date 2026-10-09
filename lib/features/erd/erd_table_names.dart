import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

/// Turns a diagram table name into what the rest of the app needs to open it.
///
/// The diagram names a PostgreSQL table of the current schema `orders` and one
/// of another schema `sales.orders` (see `ErdCatalog`). MySQL and SQLite names
/// are never qualified, so a dot there is part of the name.
abstract final class ErdTableNames {
  /// Schema used for an unqualified PostgreSQL name, as the Quick Switcher
  /// does when an object has no schema.
  static const String defaultPostgresSchema = 'public';

  /// Schema (null for the current one) and table of a diagram name.
  static (String? schema, String table) split(String name, SqlDialect dialect) {
    if (dialect != SqlDialect.postgres) return (null, name);
    final dot = name.indexOf('.');
    if (dot <= 0 || dot == name.length - 1) return (null, name);
    return (name.substring(0, dot), name.substring(dot + 1));
  }

  static String _quote(String id, SqlDialect dialect) => dialect == SqlDialect.mysql
      ? '`${id.replaceAll('`', '``')}`'
      : '"${id.replaceAll('"', '""')}"';

  /// The name as SQL: `"sales"."orders"`, `"orders"`, `` `orders` ``.
  static String qualifiedSql(String name, SqlDialect dialect) {
    final (schema, table) = split(name, dialect);
    final t = _quote(table, dialect);
    return schema == null ? t : '${_quote(schema, dialect)}.$t';
  }

  /// `SELECT * FROM <name> LIMIT <limit>;` for the SQL editor.
  static String selectSql(String name, SqlDialect dialect, {int limit = 100}) =>
      'SELECT * FROM ${qualifiedSql(name, dialect)} LIMIT $limit;';

  /// The table as the Quick Switcher opens it in the table browser.
  static QueryaSchemaObject schemaObject(
    String name,
    SqlDialect dialect, {
    required String database,
  }) {
    final (schema, table) = split(name, dialect);
    return switch (dialect) {
      SqlDialect.postgres => QueryaSchemaObject.postgres(
          database: database,
          schema: schema ?? defaultPostgresSchema,
          name: table,
          kind: QueryaSchemaObjectKind.table,
        ),
      SqlDialect.mysql => QueryaSchemaObject.mysql(
          database: database,
          name: table,
          kind: QueryaSchemaObjectKind.table,
        ),
      SqlDialect.sqlite => QueryaSchemaObject.sqlite(
          name: table,
          kind: QueryaSchemaObjectKind.table,
        ),
    };
  }
}
