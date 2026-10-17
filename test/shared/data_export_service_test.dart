import 'dart:convert';
import 'dart:io';

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

    test('writeToSink streams CSV/JSON/SQL matching format helpers', () async {
      Future<String> sinkToString(
        Future<void> Function(IOSink sink) write,
      ) async {
        final path =
            '${Directory.systemTemp.path}/querya_export_${DateTime.now().microsecondsSinceEpoch}.txt';
        final out = File(path);
        final sink = out.openWrite();
        try {
          await write(sink);
        } finally {
          await sink.close();
        }
        final text = await out.readAsString();
        await out.delete();
        return text;
      }

      final csv = await sinkToString(
        (s) => DataExportService.writeToSink(
          s,
          DataExportFormat.csv,
          columns: columns,
          rows: rows,
        ),
      );
      expect(csv, DataExportService.formatCsv(columns, rows));

      final jsonStr = await sinkToString(
        (s) => DataExportService.writeToSink(
          s,
          DataExportFormat.json,
          columns: columns,
          rows: rows,
        ),
      );
      final decoded = jsonDecode(jsonStr) as List;
      expect(decoded.length, 2);
      expect(decoded[0]['id'], '101');
      expect(decoded[1]['note'], isNull);

      final sql = await sinkToString(
        (s) => DataExportService.writeToSink(
          s,
          DataExportFormat.sqlDump,
          columns: columns,
          rows: rows,
          tableName: 'users',
        ),
      );
      expect(
        sql,
        DataExportService.formatSqlInsertDump('users', columns, rows),
      );

      final md = await sinkToString(
        (s) => DataExportService.writeToSink(
          s,
          DataExportFormat.markdown,
          columns: columns,
          rows: rows,
        ),
      );
      expect(md, DataExportService.formatMarkdownTable(columns, rows));
    });
  });

  group('formatAsync in chunks (#1537)', () {
    const columns = ['id', 'name | pipe', 'note'];
    List<List<String>> table(int n) => [
          for (var r = 0; r < n; r++)
            [
              '$r',
              r % 7 == 0 ? 'NULL' : 'n"a,me\n$r',
              if (r % 5 != 0) "it's | $r",
            ],
        ];

    String whole(DataExportFormat format, List<List<String>> rows) =>
        switch (format) {
          DataExportFormat.csv => DataExportService.formatCsv(columns, rows),
          DataExportFormat.json => DataExportService.formatJson(columns, rows),
          DataExportFormat.markdown =>
            DataExportService.formatMarkdownTable(columns, rows),
          DataExportFormat.sqlDump =>
            DataExportService.formatSqlInsertDump('t', columns, rows),
        };

    for (final format in DataExportFormat.values) {
      test('${format.name}: chunks joined give the whole document', () {
        final rows = table(23);
        for (final size in [1, 3, 7, 22, 23]) {
          final parts = <String>[];
          for (var start = 0; start < rows.length; start += size) {
            final end =
                start + size < rows.length ? start + size : rows.length;
            parts.add(DataExportService.formatChunk(
              format,
              columns,
              rows.sublist(start, end),
              't',
              first: start == 0,
              last: end == rows.length,
            ));
          }
          expect(parts.join(), whole(format, rows), reason: 'size $size');
        }
      });

      test('${format.name}: formatAsync over the hand-off size', () async {
        final rows =
            table(DataExportService.handOffCells ~/ columns.length * 2 + 5);
        final text = await DataExportService.formatAsync(
          format,
          columns: columns,
          rows: rows,
          tableName: 't',
        );
        expect(text, whole(format, rows));
      });
    }
  });
}
