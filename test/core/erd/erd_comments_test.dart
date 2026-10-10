import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';

/// #1279: table and column comments from the database.
void main() {
  test('catalog rows carry the column and table comments', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'int', '1', '0', '0', '', '1', 'NULL', 'People who sign in'],
      ['users', 'email', 'text', '0', '0', '1', '', '0', 'Lower-cased', 'People who sign in'],
      ['tags', 'id', 'int', '1', '0', '0', '', '1', '', ''],
      ['old', 'id', 'int', '1'],
    ], fkRows: const []);
    final t = {for (final t in s.tables) t.name: t};
    expect(t['users']!.comment, 'People who sign in');
    expect(t['users']!.columns.first.comment, isNull);
    expect(t['users']!.columns.last.comment, 'Lower-cased');
    expect(t['tags']!.comment, isNull, reason: 'empty is no comment');
    expect(t['old']!.comment, isNull, reason: 'short rows still read');
  });

  test('a foreign key keeps its comment', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['orders', 'user_id', 'int', '0', '0', '0', '', '0', 'Who ordered', ''],
      ['users', 'id', 'int', '1'],
    ], fkRows: const [
      ['orders', 'user_id', 'users', 'id'],
    ]);
    final fk = s.tables.firstWhere((t) => t.name == 'orders').columns.single;
    expect(fk.isForeignKey, isTrue);
    expect(fk.comment, 'Who ordered');
  });

  test('PostgreSQL and MySQL ask for comments, SQLite has none', () {
    expect(ErdCatalog.columnsSql(SqlDialect.postgres), contains('col_description'));
    expect(ErdCatalog.columnsSql(SqlDialect.postgres), contains('obj_description'));
    expect(ErdCatalog.columnsSql(SqlDialect.mysql), contains('column_comment'));
    expect(ErdCatalog.columnsSql(SqlDialect.mysql), contains('table_comment'));
    expect(ErdCatalog.columnsSql(SqlDialect.sqlite), contains('NULL AS table_comment'));
  });
}
