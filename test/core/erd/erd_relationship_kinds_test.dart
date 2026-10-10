import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';

/// #1281: one-to-one relations and junction tables.
void main() {
  test('a FK on a unique column or on the whole PK is one-to-one', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'int', '1'],
      ['profiles', 'user_id', 'int', '0', '0', '1'],
      ['orders', 'id', 'int', '1'],
      ['orders', 'user_id', 'int', '0'],
      ['passports', 'user_id', 'int', '1'],
    ], fkRows: const [
      ['profiles', 'user_id', 'users', 'id'],
      ['orders', 'user_id', 'users', 'id'],
      ['passports', 'user_id', 'users', 'id'],
    ]);
    final kind = {for (final r in s.relations) r.fromTable: r.oneToOne};
    expect(kind, {'profiles': true, 'orders': false, 'passports': true});
  });

  test('a two-FK primary key with little else is a junction table', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'int', '1'],
      ['roles', 'id', 'int', '1'],
      ['user_roles', 'user_id', 'int', '1'],
      ['user_roles', 'role_id', 'int', '1'],
      ['user_roles', 'assigned_at', 'timestamp', '0'],
    ], fkRows: const [
      ['user_roles', 'user_id', 'users', 'id'],
      ['user_roles', 'role_id', 'roles', 'id'],
    ]);
    final t = {for (final t in s.tables) t.name: t};
    expect(t['user_roles']!.isJunction, isTrue);
    expect(t['users']!.isJunction, isFalse);
  });
}
