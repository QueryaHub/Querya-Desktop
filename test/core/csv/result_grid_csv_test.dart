import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/csv/result_grid_csv.dart';

void main() {
  group('resultGridAsCsv', () {
    test('escapes commas and quotes', () {
      expect(
        resultGridAsCsv(
          const ['a', 'b'],
          const [
            ['1', 'two,comma'],
            ['quote', 'say "hi"'],
          ],
        ),
        'a,b\n1,"two,comma"\nquote,"say ""hi"""',
      );
    });

    test('pads short rows', () {
      expect(
        resultGridAsCsv(const [
          'x',
          'y',
          'z'
        ], const [
          ['only'],
        ]),
        'x,y,z\nonly,,',
      );
    });
  });

  group('resultGridAsCsvAsync', () {
    test('matches synchronous result off the UI isolate', () async {
      const columns = ['a', 'b'];
      const rows = [
        ['1', 'two,comma'],
        ['quote', 'say "hi"'],
      ];
      final asyncCsv = await resultGridAsCsvAsync(columns, rows);
      expect(asyncCsv, resultGridAsCsv(columns, rows));
    });
  });

  group('writeResultGridCsv', () {
    test('streams the same content as resultGridAsCsv', () async {
      const columns = ['a', 'b'];
      const rows = [
        ['1', 'two,comma'],
        ['quote', 'say "hi"'],
      ];
      final file = File(
        '${Directory.systemTemp.path}/querya_csv_stream_${DateTime.now().microsecondsSinceEpoch}.csv',
      );
      try {
        final sink = file.openWrite();
        await writeResultGridCsv(sink, columns: columns, rows: rows);
        await sink.close();
        expect(await file.readAsString(), resultGridAsCsv(columns, rows));
      } finally {
        if (await file.exists()) await file.delete();
      }
    });

    test('streams large grids without building one giant string first', () async {
      const columns = ['id', 'value'];
      final rows = List.generate(
        2500,
        (i) => ['$i', 'value_$i'],
        growable: false,
      );
      final file = File(
        '${Directory.systemTemp.path}/querya_csv_large_${DateTime.now().microsecondsSinceEpoch}.csv',
      );
      try {
        final sink = file.openWrite();
        await writeResultGridCsv(sink, columns: columns, rows: rows);
        await sink.close();
        final lines = await file.readAsLines();
        expect(lines.length, 2501);
        expect(lines.first, 'id,value');
        expect(lines[1], '0,value_0');
        expect(lines.last, '2499,value_2499');
      } finally {
        if (await file.exists()) await file.delete();
      }
    });
  });
}
