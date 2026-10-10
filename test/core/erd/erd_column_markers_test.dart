import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';

/// #1277: unique, default and identity come from the catalog.
void main() {
  test('catalog rows carry unique, default and identity', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['users', 'id', 'integer', '1', '0', '0', "nextval('users_id_seq'::regclass)", '1'],
      ['users', 'email', 'text', '0', '0', '1', 'NULL', '0'],
      ['users', 'status', 'text', '0', '1', '0', "'active'::text", '0'],
      ['users', 'note', 'text', '0', '1'],
    ], fkRows: const []);
    final c = {for (final c in s.tables.single.columns) c.name: c};

    expect(c['id']!.isIdentity, isTrue);
    expect(c['id']!.badges, ['AI'], reason: 'a PK is not also "unique"');
    expect(c['email']!.isUnique, isTrue);
    expect(c['email']!.defaultValue, isNull, reason: 'NULL is no default');
    expect(c['email']!.badges, ['UQ']);
    expect(c['status']!.defaultValue, "'active'::text");
    expect(c['status']!.badges, ['DF']);
    expect(c['note']!.badges, isEmpty, reason: 'old five-column rows still read');
  });

  test('a foreign key keeps the markers', () {
    final s = ErdSchema.fromCatalog(columnRows: const [
      ['orders', 'user_id', 'int', '0', '0', '1', '', '0'],
      ['users', 'id', 'int', '1', '0', '0', '', '1'],
    ], fkRows: const [
      ['orders', 'user_id', 'users', 'id'],
    ]);
    final fk = s.tables.firstWhere((t) => t.name == 'orders').columns.single;
    expect(fk.isForeignKey, isTrue);
    expect(fk.isUnique, isTrue);
  });

  test('every dialect asks the catalog for the markers', () {
    for (final d in SqlDialect.values) {
      final sql = ErdCatalog.columnsSql(d);
      expect(sql.toLowerCase(), contains('default'), reason: d.name);
    }
    expect(ErdCatalog.columnsSql(SqlDialect.postgres), contains('attidentity'));
    expect(ErdCatalog.columnsSql(SqlDialect.postgres), contains('indisunique'));
    expect(ErdCatalog.columnsSql(SqlDialect.mysql), contains("'UNI'"));
    expect(ErdCatalog.columnsSql(SqlDialect.mysql), contains('auto_increment'));
    expect(ErdCatalog.columnsSql(SqlDialect.sqlite), contains('pragma_index_list'));
    expect(ErdCatalog.columnsSql(SqlDialect.sqlite), contains('dflt_value'));
  });
}
