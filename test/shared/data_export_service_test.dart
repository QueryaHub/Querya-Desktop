import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/shared/services/data_export_service.dart';

void main() {
  group('DataExportService', () {
    final columns = ['id', 'user_name', 'note'];
    final rows = [
      ['101', 'Alice "Queen"', 'First\nline'],
      ['102', 'Bob\'s data', 'NULL'],
    ];

    test('formatCsv escapes quotes and newlines accurately', () {
      final csv = DataExportService.formatCsv(columns, rows);
      expect(csv, contains('id,user_name,note'));
      expect(csv, contains('"Alice ""Queen"""'));
      expect(csv, contains('"First\nline"'));
    });

    test('formatJson creates object array by default', () {
      final jsonStr = DataExportService.formatJson(columns, rows);
      final decoded = jsonDecode(jsonStr) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['id'], '101');
      expect(decoded[0]['user_name'], 'Alice "Queen"');
      expect(decoded[0]['note'], 'First\nline');
      expect(decoded[1]['note'], isNull); // 'NULL' converted to null
    });

    test('formatJson creates table dict when asObjectArray is false', () {
      final jsonStr =
          DataExportService.formatJson(columns, rows, asObjectArray: false);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      expect(decoded['columns'], ['id', 'user_name', 'note']);
      expect((decoded['rows'] as List).length, 2);
    });

    test('formatMarkdownTable escapes pipes and formats header', () {
      final md = DataExportService.formatMarkdownTable(columns, rows);
      expect(md, contains('| id | user_name | note |'));
      expect(md, contains('| --- | --- | --- |'));
      expect(md, contains('| 101 | Alice "Queen" | First line |'));
      expect(md, contains('Bob\'s data'));
      expect(md, contains('`NULL`'));
    });

    test('formatSqlInsertDump escapes single quotes and generates valid SQL', () {
      final sql = DataExportService.formatSqlInsertDump('users', columns, rows);
      expect(
          sql,
          contains(
              "INSERT INTO users (id, user_name, note) VALUES ('101', 'Alice \"Queen\"', 'First\nline');"));
      expect(
          sql,
          contains(
              "INSERT INTO users (id, user_name, note) VALUES ('102', 'Bob''s data', NULL);"));
    });

    test('formatAsync handles formatting off-thread', () async {
      final md = await DataExportService.formatAsync(
        DataExportFormat.markdown,
        columns: columns,
        rows: rows,
      );
      expect(md, contains('| id | user_name | note |'));
    });
  });
}
