import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/actions/querya_schema_object.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_cache.dart';
import 'package:querya_desktop/core/actions/querya_schema_object_loader.dart';
import 'package:querya_desktop/core/sdui/sdui_tree_schema.dart';

void main() {
  final cache = QueryaSchemaObjectCache.instance;

  setUp(cache.resetForTest);
  tearDown(cache.resetForTest);

  QueryaSchemaObject users() => QueryaSchemaObject.postgres(
        database: 'app',
        schema: 'public',
        name: 'users',
        kind: QueryaSchemaObjectKind.table,
      );

  QueryaSchemaObject orders() => QueryaSchemaObject.postgres(
        database: 'app',
        schema: 'sales',
        name: 'orders',
        kind: QueryaSchemaObjectKind.table,
      );

  test('filter matches name, schema.qualified, and kind', () {
    final pool = [users(), orders()];
    expect(
      filterSchemaObjects(pool, 'users').map((o) => o.id),
      [users().id],
    );
    expect(
      filterSchemaObjects(pool, 'public.users').map((o) => o.id),
      [users().id],
    );
    expect(
      filterSchemaObjects(pool, 'sales').map((o) => o.id),
      [orders().id],
    );
  });

  test('filter caps results and ignores extra spaces', () {
    final pool = [
      for (var i = 0; i < 120; i++)
        QueryaSchemaObject.sqlite(
          name: 't$i',
          kind: QueryaSchemaObjectKind.table,
        ),
    ];
    expect(filterSchemaObjects(pool, '', limit: 80), hasLength(80));
    expect(filterSchemaObjects(pool, '  t1  ', limit: 5), isNotEmpty);
  });

  test('cache peek/put/merge/invalidate', () {
    const scope = 'pg:app';
    cache.put(1, scope, [users()]);
    expect(cache.peek(1, scope)!.map((o) => o.name), ['users']);

    cache.merge(1, scope, [orders()]);
    expect(cache.peek(1, scope)!.map((o) => o.qualifiedName).toList()..sort(), [
      'public.users',
      'sales.orders',
    ]);

    cache.invalidate(1);
    expect(cache.peek(1, scope), isNull);
  });

  test('flattenExtensionTree collects table-like leaves', () {
    const schema = SduiTreeSchema(
      roots: [
        SduiTreeNode(
          id: 'db.app',
          label: 'app',
          children: [
            SduiTreeNode(id: 'table.app.users', label: 'users'),
            SduiTreeNode(id: 'view.app.active_users', label: 'active_users'),
            SduiTreeNode(id: 'folder.app.misc', label: 'misc'),
          ],
        ),
      ],
    );
    final objects = flattenExtensionTree(schema);
    expect(objects.map((o) => o.name), ['users', 'active_users']);
    expect(objects[1].kind, QueryaSchemaObjectKind.view);
  });
}
