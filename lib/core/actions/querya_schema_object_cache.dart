import 'package:flutter/foundation.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';

/// In-memory schema snapshot per connection / database.
///
/// Tree loaders [merge] as they fetch; the Quick Switcher [peek]s first and
/// only hits the network when a scope is empty.
class QueryaSchemaObjectCache {
  QueryaSchemaObjectCache._();

  static final QueryaSchemaObjectCache instance = QueryaSchemaObjectCache._();

  final Map<String, List<QueryaSchemaObject>> _scopes = {};

  static String scopePostgres(String database) => 'pg:$database';
  static String scopeMysql(String database) => 'mysql:$database';
  static String scopeSqlite() => 'sqlite';
  static String scopeMongo(String database) => 'mongo:$database';
  static String scopeExtension() => 'ext';

  static String key(int connectionId, String scope) => '$connectionId|$scope';

  List<QueryaSchemaObject>? peek(int connectionId, String scope) {
    final items = _scopes[key(connectionId, scope)];
    if (items == null) return null;
    return List<QueryaSchemaObject>.unmodifiable(items);
  }

  void put(
    int connectionId,
    String scope,
    List<QueryaSchemaObject> objects,
  ) {
    final copy = List<QueryaSchemaObject>.from(objects)
      ..sort((a, b) => a.qualifiedName.compareTo(b.qualifiedName));
    _scopes[key(connectionId, scope)] = copy;
  }

  /// Upserts [objects] into an existing snapshot (tree folder loads).
  void merge(
    int connectionId,
    String scope,
    List<QueryaSchemaObject> objects,
  ) {
    if (objects.isEmpty) return;
    final existing = _scopes[key(connectionId, scope)] ?? const [];
    final byId = <String, QueryaSchemaObject>{
      for (final object in existing) object.id: object,
    };
    for (final object in objects) {
      byId[object.id] = object;
    }
    put(connectionId, scope, byId.values.toList());
  }

  void invalidate(int connectionId) {
    _scopes.removeWhere((k, _) => k.startsWith('$connectionId|'));
  }

  @visibleForTesting
  void resetForTest() => _scopes.clear();
}
