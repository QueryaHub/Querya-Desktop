import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_layout.dart';
import 'package:querya_desktop/core/erd/erd_layout_engine.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';
import 'package:querya_desktop/core/erd/erd_saved_layout.dart';

ErdColumn _col(
  String name, {
  bool pk = false,
  bool fk = false,
}) =>
    ErdColumn(name: name, type: 'int', isPrimaryKey: pk, isForeignKey: fk);

ErdRelation _rel(String from, String to) => ErdRelation(
      fromTable: from,
      fromColumn: '${to}_id',
      toTable: to,
      toColumn: 'id',
    );

void main() {
  final users = ErdTable(
    name: 'users',
    columns: [_col('id', pk: true), _col('name')],
  );
  final orders = ErdTable(
    name: 'orders',
    columns: [_col('id', pk: true), _col('users_id', fk: true)],
  );
  final roles = ErdTable(
    name: 'roles',
    columns: [_col('id', pk: true), _col('label')],
  );
  final userRoles = ErdTable(
    name: 'user_roles',
    columns: [
      _col('users_id', pk: true, fk: true),
      _col('roles_id', pk: true, fk: true),
    ],
  );
  final schema = ErdSchema(
    tables: [users, orders, roles, userRoles],
    relations: [
      _rel('orders', 'users'),
      _rel('user_roles', 'users'),
      _rel('user_roles', 'roles'),
    ],
  );

  group('ErdLayoutEngine.focusIn', () {
    test('returns null without a focus table', () {
      expect(ErdLayoutEngine.focusIn(schema, null), isNull);
    });

    test('returns the table when the schema names it', () {
      expect(ErdLayoutEngine.focusIn(schema, 'orders'), 'orders');
    });

    test('falls back to the bare name of a schema-qualified table', () {
      expect(ErdLayoutEngine.focusIn(schema, 'public.orders'), 'orders');
    });

    test('returns null for an unknown table', () {
      expect(ErdLayoutEngine.focusIn(schema, 'public.missing'), isNull);
    });
  });

  group('ErdLayoutEngine.visibleOf', () {
    test('hides tables and drops their relations', () {
      final visible = ErdLayoutEngine.visibleOf(
        schema,
        hidden: {'users'},
        collapsed: const {},
        detail: ErdDetail.all,
      );
      expect(visible.tables.map((t) => t.name),
          ['orders', 'roles', 'user_roles']);
      expect(visible.relations.map((r) => '${r.fromTable}>${r.toTable}'),
          ['user_roles>roles']);
    });

    test('collapsed tables lose their columns', () {
      final visible = ErdLayoutEngine.visibleOf(
        schema,
        hidden: const {},
        collapsed: {'orders'},
        detail: ErdDetail.all,
      );
      final ordersTable = visible.tables.firstWhere((t) => t.name == 'orders');
      expect(ordersTable.columns, isEmpty);
    });

    test('keys detail keeps only primary and foreign key columns', () {
      final visible = ErdLayoutEngine.visibleOf(
        schema,
        hidden: const {},
        collapsed: const {},
        detail: ErdDetail.keys,
      );
      final usersTable = visible.tables.firstWhere((t) => t.name == 'users');
      expect(usersTable.columns.map((c) => c.name), ['id']);
    });

    test('names detail drops all columns', () {
      final visible = ErdLayoutEngine.visibleOf(
        schema,
        hidden: const {},
        collapsed: const {},
        detail: ErdDetail.names,
      );
      expect(visible.tables.every((t) => t.columns.isEmpty), isTrue);
    });
  });

  group('ErdLayoutEngine graph helpers', () {
    test('neighbourMap relates tables both ways', () {
      final map = ErdLayoutEngine.neighbourMap(schema);
      expect(map['users'], {'orders', 'user_roles'});
      expect(map['orders'], {'users'});
      expect(map['roles'], {'user_roles'});
    });

    test('junctionMap names the tables a link table links', () {
      final map = ErdLayoutEngine.junctionMap(schema);
      expect(map.keys, ['user_roles']);
      expect(map['user_roles'], 'users and roles');
    });

    test('isFocusedIn is true for the focus and its neighbours', () {
      final map = ErdLayoutEngine.neighbourMap(schema);
      expect(ErdLayoutEngine.isFocusedIn(map, null, 'users'), isFalse);
      expect(ErdLayoutEngine.isFocusedIn(map, 'users', 'users'), isTrue);
      expect(ErdLayoutEngine.isFocusedIn(map, 'users', 'orders'), isTrue);
      expect(ErdLayoutEngine.isFocusedIn(map, 'users', 'roles'), isFalse);
    });
  });

  group('ErdLayoutEngine.matches', () {
    test('matches names case-insensitively', () {
      expect(
        ErdLayoutEngine.matches(schema, 'ROLE').map((t) => t.name),
        ['roles', 'user_roles'],
      );
    });

    test('caps the result at the limit', () {
      expect(ErdLayoutEngine.matches(schema, '', limit: 2), hasLength(2));
    });
  });

  group('ErdLayoutEngine.withSaved', () {
    test('returns the computed layout when nothing is saved', () {
      final computed = ErdLayout.compute(schema);
      expect(
        identical(ErdLayoutEngine.withSaved(computed, null), computed),
        isTrue,
      );
      expect(
        identical(
          ErdLayoutEngine.withSaved(computed, const ErdSavedLayout()),
          computed,
        ),
        isTrue,
      );
    });

    test('puts saved cards back and keeps the others out of their way', () {
      final computed = ErdLayout.compute(schema);
      const savedAt = Offset(500, 40);
      final merged = ErdLayoutEngine.withSaved(
        computed,
        const ErdSavedLayout(positions: {'users': savedAt}),
      );
      expect(merged.positions['users'], savedAt);
      final savedRight = savedAt.dx + computed.widthFor('users');
      for (final name in ['orders', 'roles', 'user_roles']) {
        expect(merged.positions[name]!.dx, greaterThan(savedRight));
      }
    });
  });
}
