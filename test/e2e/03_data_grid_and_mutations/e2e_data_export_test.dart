import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

void main() {
  const columns = ['id', 'name', 'note'];
  final rows = [
    ['1', 'Alice', 'say "hi", ok'],
    ['2', 'Bob', 'NULL'],
  ];

  test('CSV quotes commas and quotes', () {
    final csv = DataExportService.formatCsv(columns, rows);
    final lines = const LineSplitter().convert(csv);
    expect(lines.first, 'id,name,note');
    expect(lines[1], '1,Alice,"say ""hi"", ok"');
    expect(lines.length, 3);
  });

  test('JSON is an array of objects', () {
    final decoded = jsonDecode(DataExportService.formatJson(columns, rows))
        as List<dynamic>;
    expect(decoded.length, 2);
    expect((decoded.first as Map)['name'], 'Alice');
    expect((decoded.first as Map)['note'], 'say "hi", ok');
  });

  test('Markdown has header, separator and one line per row', () {
    final md = DataExportService.formatMarkdownTable(columns, rows);
    final lines = md.trim().split('\n');
    expect(lines.first, contains('id'));
    expect(lines[1], contains('---'));
    expect(lines.length, 4);
    expect(md, contains('`NULL`'));
  });

  test('SQL dump emits one INSERT per row for the named table', () {
    final sql = DataExportService.formatSqlInsertDump('people', columns, rows);
    expect('INSERT INTO'.allMatches(sql).length, 2);
    expect(sql, contains('people'));
    expect(sql, contains("'Alice'"));
  });

  test('empty selections export nothing harmful', () {
    expect(DataExportService.formatMarkdownTable([], []), '');
    expect(DataExportService.formatSqlInsertDump('t', columns, []), '');
  });
}
