import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/core/erd/erd_catalog.dart';
import 'package:querya_desktop/core/erd/erd_model.dart';

/// #1280: enum labels and domain base types.
List<String> _row(String type, {String values = '', String base = ''}) =>
    ['t', 'c', type, '0', '1', '0', '', '0', '', '', values, base];

ErdColumn _col(List<String> row) =>
    ErdSchema.fromCatalog(columnRows: [row], fkRows: const [])
        .tables
        .single
        .columns
        .single;

void main() {
  test('PostgreSQL labels come in order, separated by U+001F', () {
    final c = _col(_row('user_role_enum',
        values: 'admin\u001feditor\u001fviewer'));
    expect(c.enumValues, ['admin', 'editor', 'viewer']);
    expect(c.badges, contains('EN'));
  });

  test("MySQL enum('a','b') is read from the type, quotes unescaped", () {
    final c = _col(_row("enum('new','it''s paid','a,b')"));
    expect(c.enumValues, ['new', "it's paid", 'a,b']);
  });

  test('a domain reports its base type; plain columns have neither', () {
    final d = _col(_row('positive_int', base: 'integer'));
    expect(d.domainBase, 'integer');
    expect(d.enumValues, isEmpty);
    final plain = _col(['t', 'c', 'text', '0']);
    expect(plain.enumValues, isEmpty);
    expect(plain.domainBase, isNull);
    expect(plain.badges, isEmpty);
  });

  test('the PostgreSQL catalog asks pg_enum and the domain base', () {
    final sql = ErdCatalog.columnsSql(SqlDialect.postgres);
    expect(sql, contains('pg_enum'));
    expect(sql, contains('typbasetype'));
  });
}
