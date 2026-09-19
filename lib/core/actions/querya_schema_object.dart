import 'package:flutter/widgets.dart';
import 'package:querya_desktop/core/ui/querya_icons.dart';

/// Browsable object the Quick Switcher can jump to.
enum QueryaSchemaObjectKind {
  table,
  view,
  materializedView,
  collection,
}

@immutable
class QueryaSchemaObject {
  const QueryaSchemaObject({
    required this.id,
    required this.name,
    required this.kind,
    this.schema,
    this.database,
    this.rowCount,
  });

  factory QueryaSchemaObject.postgres({
    required String database,
    required String schema,
    required String name,
    required QueryaSchemaObjectKind kind,
    int? rowCount,
  }) {
    return QueryaSchemaObject(
      id: 'pg:$database:$schema:${kind.name}:$name',
      name: name,
      schema: schema,
      database: database,
      kind: kind,
      rowCount: rowCount,
    );
  }

  factory QueryaSchemaObject.mysql({
    required String database,
    required String name,
    required QueryaSchemaObjectKind kind,
    int? rowCount,
  }) {
    return QueryaSchemaObject(
      id: 'mysql:$database:${kind.name}:$name',
      name: name,
      database: database,
      kind: kind,
      rowCount: rowCount,
    );
  }

  factory QueryaSchemaObject.sqlite({
    required String name,
    required QueryaSchemaObjectKind kind,
    int? rowCount,
  }) {
    return QueryaSchemaObject(
      id: 'sqlite:${kind.name}:$name',
      name: name,
      kind: kind,
      rowCount: rowCount,
    );
  }

  factory QueryaSchemaObject.mongo({
    required String database,
    required String name,
    int? rowCount,
  }) {
    return QueryaSchemaObject(
      id: 'mongo:$database:$name',
      name: name,
      database: database,
      kind: QueryaSchemaObjectKind.collection,
      rowCount: rowCount,
    );
  }

  factory QueryaSchemaObject.extension({
    required String database,
    required String name,
    QueryaSchemaObjectKind kind = QueryaSchemaObjectKind.table,
  }) {
    return QueryaSchemaObject(
      id: 'ext:$database:${kind.name}:$name',
      name: name,
      database: database,
      kind: kind,
    );
  }

  final String id;
  final String name;
  final String? schema;
  final String? database;
  final QueryaSchemaObjectKind kind;
  final int? rowCount;

  String get qualifiedName {
    if (schema != null && schema!.isNotEmpty) return '$schema.$name';
    if (database != null && database!.isNotEmpty) return '$database.$name';
    return name;
  }

  String get kindLabel => switch (kind) {
        QueryaSchemaObjectKind.table => 'Table',
        QueryaSchemaObjectKind.view => 'View',
        QueryaSchemaObjectKind.materializedView => 'Materialized view',
        QueryaSchemaObjectKind.collection => 'Collection',
      };

  IconData get icon => switch (kind) {
        QueryaSchemaObjectKind.table => QueryaIcons.tableLeaf,
        QueryaSchemaObjectKind.view => QueryaIcons.viewLeaf,
        QueryaSchemaObjectKind.materializedView =>
          QueryaIcons.materializedViewLeaf,
        QueryaSchemaObjectKind.collection => QueryaIcons.database,
      };

  /// Fields the switcher matches against (`users` → `public.users`).
  String get searchHaystack =>
      '$name ${qualifiedName} ${kind.name} ${kindLabel} ${database ?? ''} ${schema ?? ''}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is QueryaSchemaObject && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// In-memory substring filter. Works on a cached snapshot — never I/O.
///
/// Top-level so large lists can run via [compute] without capturing the UI
/// isolate. Caps [limit] so the list stays cheap to build.
List<QueryaSchemaObject> filterSchemaObjects(
  List<QueryaSchemaObject> objects,
  String query, {
  int limit = 80,
}) {
  if (objects.isEmpty || limit <= 0) return const [];
  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    return objects.length <= limit ? objects : objects.sublist(0, limit);
  }
  final parts = q.split(RegExp(r'\s+'));
  final hits = <QueryaSchemaObject>[];
  for (final object in objects) {
    final hay = object.searchHaystack.toLowerCase();
    if (parts.every(hay.contains)) {
      hits.add(object);
      if (hits.length >= limit) break;
    }
  }
  return hits;
}
