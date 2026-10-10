import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';
import 'package:querya_desktop/features/erd/erd_export.dart';

/// #1285: the DBML text, as dbdiagram and dbdocs read it.
///
/// Catalog rows: table, column, type, isPk, isNullable, isUnique, default,
/// isIdentity, column comment, table comment, enum values (U+001F), domain.
ErdSchema _sample() => ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'integer', '1', '0', '0', '', '1'],
      ['users', 'email', 'character varying(255)', '0', '0', '1', '', '0',
        'Login address'],
      [
        'users', 'created_at', 'timestamp with time zone', '0', '0', '0',
        'now()', '0'
      ],
      ['profiles', 'user_id', 'integer', '0', '0', '1'],
      ['orders', 'id', 'integer', '1', '0', '0', '', '1', '', 'Customer orders'],
      ['orders', 'user_id', 'integer', '0', '1'],
      [
        'orders', 'status', 'order_status', '0', '0', '0',
        "'new'::order_status", '0', '', '', 'new\u001Fpaid\u001Fshipped'
      ],
      ['sales.order_items', 'order_id', 'integer', '1'],
      ['sales.order_items', 'line', 'integer', '1'],
      ['sales.order_items', 'note', 'text', '0', '1', '0', "'it''s'", '0'],
    ], fkRows: const [
      ['profiles', 'user_id', 'users', 'id'],
      ['orders', 'user_id', 'users', 'id'],
    ]);

const _golden = '''// Exported from Querya

Enum "order_status" {
  "new"
  "paid"
  "shipped"
}

Table "users" [headercolor: #3366ff] {
  "id" integer [pk, increment]
  "email" "character varying(255)" [not null, unique, note: 'Login address']
  "created_at" "timestamp with time zone" [not null, default: `now()`]
}

Table "profiles" {
  "user_id" integer [not null, unique]
}

Table "orders" [note: 'Customer orders'] {
  "id" integer [pk, increment]
  "user_id" integer
  "status" "order_status" [not null, default: 'new']
}

Table "sales"."order_items" {
  "order_id" integer [not null]
  "line" integer [not null]
  "note" text [default: 'it\\'s']

  indexes {
    ("order_id", "line") [pk]
  }
}

Ref: "profiles"."user_id" - "users"."id"
Ref: "orders"."user_id" > "users"."id"

TableGroup "Billing" [note: 'Money'] {
  "orders"
  "sales"."order_items"
}

Note "note_n1" {
  'Check **FK** order'
}
''';

void main() {
  test('the sample schema exports as the golden text', () {
    final dbml = ErdExport.toDbml(
      _sample(),
      headerColors: const {'users': '#3366ff'},
      groups: const [
        ErdGroup(
          id: 'g1',
          name: 'Billing',
          color: 'type1',
          note: 'Money',
          tables: ['orders', 'sales.order_items', 'gone'],
        ),
      ],
      notes: const [ErdNote(id: 'n1', text: 'Check **FK** order', x: 0, y: 0)],
    );
    expect(dbml, _golden);
  });

  test('a group of tables that are not shown is left out', () {
    final dbml = ErdExport.toDbml(_sample(), groups: const [
      ErdGroup(id: 'g', name: 'Away', color: 'type1', tables: ['gone']),
    ]);
    expect(dbml, isNot(contains('TableGroup')));
  });

  test('a multi-line note is a triple-quoted block, quotes are escaped', () {
    final s = ErdSchema.fromCatalog(
        columnRows: const [['t', 'id', 'int', '1']], fkRows: const []);
    final dbml = ErdExport.toDbml(s, notes: const [
      ErdNote(id: 'a', text: 'one\ntwo', x: 0, y: 0),
      ErdNote(id: 'b', text: "it's", x: 0, y: 0),
    ]);
    expect(dbml, contains("Note \"note_a\" {\n  '''\none\ntwo\n'''\n}"));
    expect(dbml, contains(r"'it\'s'"));
  });

  test('a table without relations or groups has no Ref or TableGroup', () {
    final s = ErdSchema.fromCatalog(
        columnRows: const [['t', 'id', 'int', '1']], fkRows: const []);
    final dbml = ErdExport.toDbml(s);
    expect(dbml, isNot(contains('Ref:')));
    expect(dbml, isNot(contains('TableGroup')));
    expect(dbml, contains('Table "t" {\n  "id" int [pk]\n}'));
  });
}
