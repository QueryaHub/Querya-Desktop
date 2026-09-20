import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_cache.dart';
import 'package:querya_desktop/core/database/mongodb_service.dart';
import 'package:querya_desktop/core/database/mysql_service.dart';
import 'package:querya_desktop/core/database/postgres_service.dart';
import 'package:querya_desktop/core/database/sqlite_service.dart';
import 'package:querya_desktop/core/extensions/extension_driver_session.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';
import 'package:querya_desktop/core/storage/local_db.dart';

const _extensionTableLikeKinds = {
  'table',
  'view',
  'dict',
  'dictionary',
  'materialized-view',
  'mv',
};

/// Loads browsable objects once per connection scope, then serves the cache.
class QueryaSchemaObjectLoader {
  QueryaSchemaObjectLoader._();

  /// [database] is the PG / MySQL / extension catalog. [mongoDatabase] is the
  /// active Mongo DB (collections live there).
  static Future<List<QueryaSchemaObject>> load({
    required ConnectionRow? connection,
    String? database,
    String? mongoDatabase,
  }) async {
    if (connection == null || connection.id == null) {
      return const [];
    }
    final id = connection.id!;
    final type = connection.type.toLowerCase();
    final cache = QueryaSchemaObjectCache.instance;

    switch (type) {
      case 'postgres':
      case 'postgresql':
        final db = (database ?? connection.databaseName)?.trim();
        if (db == null || db.isEmpty) return const [];
        final scope = QueryaSchemaObjectCache.scopePostgres(db);
        final cached = cache.peek(id, scope);
        if (cached != null && cached.isNotEmpty) return cached;
        final fetched = await _loadPostgres(connection, db);
        cache.put(id, scope, fetched);
        return fetched;
      case 'mysql':
        final db = (database ?? connection.databaseName)?.trim();
        if (db == null || db.isEmpty) return const [];
        final scope = QueryaSchemaObjectCache.scopeMysql(db);
        final cached = cache.peek(id, scope);
        if (cached != null && cached.isNotEmpty) return cached;
        final fetched = await _loadMysql(connection, db);
        cache.put(id, scope, fetched);
        return fetched;
      case 'sqlite':
        final cached = cache.peek(id, QueryaSchemaObjectCache.scopeSqlite());
        if (cached != null && cached.isNotEmpty) return cached;
        final fetched = await _loadSqlite(connection);
        cache.put(id, QueryaSchemaObjectCache.scopeSqlite(), fetched);
        return fetched;
      case 'mongodb':
        final db = (mongoDatabase ?? connection.databaseName)?.trim();
        if (db == null || db.isEmpty) return const [];
        final scope = QueryaSchemaObjectCache.scopeMongo(db);
        final cached = cache.peek(id, scope);
        if (cached != null && cached.isNotEmpty) return cached;
        final fetched = await _loadMongo(connection, db);
        cache.put(id, scope, fetched);
        return fetched;
      default:
        if (!connection.isExtensionDriver) return const [];
        final scope = QueryaSchemaObjectCache.scopeExtension();
        final cached = cache.peek(id, scope);
        if (cached != null && cached.isNotEmpty) return cached;
        final fetched = await _loadExtension(connection);
        cache.put(id, scope, fetched);
        return fetched;
    }
  }

  static Future<List<QueryaSchemaObject>> _loadPostgres(
    ConnectionRow connection,
    String database,
  ) async {
    final lease = await PostgresService.instance.acquire(
      connection,
      database: database,
      mode: PgSessionMode.readOnly,
    );
    try {
      final rows = await lease.connection.listBrowsableRelations();
      return [
        for (final row in rows)
          QueryaSchemaObject.postgres(
            database: database,
            schema: row.schema,
            name: row.name,
            kind: switch (row.kind) {
              'view' => QueryaSchemaObjectKind.view,
              'matview' => QueryaSchemaObjectKind.materializedView,
              _ => QueryaSchemaObjectKind.table,
            },
          ),
      ];
    } finally {
      lease.release();
    }
  }

  static Future<List<QueryaSchemaObject>> _loadMysql(
    ConnectionRow connection,
    String database,
  ) async {
    final lease = await MysqlService.instance.acquire(
      connection,
      database: database,
      mode: MysqlSessionMode.readOnly,
    );
    try {
      final tables = await lease.connection.listTables(schema: database);
      final views = await lease.connection.listViews(schema: database);
      return [
        for (final name in tables)
          QueryaSchemaObject.mysql(
            database: database,
            name: name,
            kind: QueryaSchemaObjectKind.table,
          ),
        for (final name in views)
          QueryaSchemaObject.mysql(
            database: database,
            name: name,
            kind: QueryaSchemaObjectKind.view,
          ),
      ];
    } finally {
      lease.release();
    }
  }

  static Future<List<QueryaSchemaObject>> _loadSqlite(
    ConnectionRow connection,
  ) async {
    final lease = await SqliteService.instance.acquire(
      connection,
      mode: SqliteSessionMode.readOnly,
    );
    try {
      final tables = await lease.connection.listTables();
      final views = await lease.connection.listViews();
      return [
        for (final name in tables)
          QueryaSchemaObject.sqlite(
            name: name,
            kind: QueryaSchemaObjectKind.table,
          ),
        for (final name in views)
          QueryaSchemaObject.sqlite(
            name: name,
            kind: QueryaSchemaObjectKind.view,
          ),
      ];
    } finally {
      lease.release();
    }
  }

  static Future<List<QueryaSchemaObject>> _loadMongo(
    ConnectionRow connection,
    String database,
  ) async {
    final conn = await MongoService.instance.ensureConnected(connection);
    final names = await conn.listCollections(database);
    return [
      for (final name in names)
        QueryaSchemaObject.mongo(database: database, name: name),
    ];
  }

  static Future<List<QueryaSchemaObject>> _loadExtension(
    ConnectionRow connection,
  ) async {
    final schema =
        await ExtensionDriverSession.instance.getSchemaTree(connection);
    return flattenExtensionTree(schema);
  }
}

/// Collects table-like SDUI nodes already present in [schema] (no expand).
List<QueryaSchemaObject> flattenExtensionTree(SduiTreeSchema schema) {
  final out = <QueryaSchemaObject>[];
  void walk(SduiTreeNode node) {
    final parts = node.id.split('.');
    if (parts.length >= 3 && _extensionTableLikeKinds.contains(parts[0])) {
      final kind = parts[0] == 'view' ||
              parts[0] == 'materialized-view' ||
              parts[0] == 'mv'
          ? QueryaSchemaObjectKind.view
          : QueryaSchemaObjectKind.table;
      out.add(
        QueryaSchemaObject.extension(
          database: parts[1],
          name: parts.sublist(2).join('.'),
          kind: kind,
        ),
      );
    }
    for (final child in node.children) {
      walk(child);
    }
  }

  for (final root in schema.roots) {
    walk(root);
  }
  return out;
}
