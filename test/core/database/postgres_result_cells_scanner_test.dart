import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/database/postgres_result_cells.dart';

void main() {
  group('postgresByteaHexDisplay (#1529, #1521)', () {
    test('writes \\x and two lower-case hex digits per byte', () {
      expect(postgresByteaHexDisplay(Uint8List(0)), r'\x');
      expect(
        postgresByteaHexDisplay(Uint8List.fromList([0, 1, 15, 16, 171, 255])),
        r'\x00010f10abff',
      );
    });

    test('every byte value maps to its two digits', () {
      final all = Uint8List.fromList(List.generate(256, (i) => i));
      final text = postgresByteaHexDisplay(all);
      expect(text.length, 2 + 512);
      for (var i = 0; i < 256; i++) {
        expect(text.substring(2 + i * 2, 4 + i * 2),
            i.toRadixString(16).padLeft(2, '0'));
      }
    });

    test('cell display goes through the same encoder', () {
      expect(
        postgresResultCellToDisplayString(Uint8List.fromList([222, 173])),
        r'\xdead',
      );
    });
  });

  group('date-only cells (#1529, #1521)', () {
    test('a date column shows only the date', () {
      expect(
        postgresResultCellToDisplayString(
          DateTime.utc(2026, 1, 5),
          typeOid: Type.date.oid,
        ),
        '2026-01-05',
      );
      expect(
        postgresResultCellToDisplayString(
          DateTime(2026, 1, 5, 13, 30),
          dataTypeName: 'date',
        ),
        '2026-01-05',
      );
    });

    test('years outside 0..9999 keep their sign and digits', () {
      expect(
        postgresResultCellToDisplayString(
          DateTime.utc(12000, 3, 4),
          typeOid: Type.date.oid,
        ),
        '+012000-03-04',
      );
    });

    test('timestamps keep the full ISO text', () {
      expect(
        postgresResultCellToDisplayString(
          DateTime.utc(2026, 1, 5, 7, 8, 9),
          typeOid: Type.timestamp.oid,
        ),
        '2026-01-05T07:08:09.000Z',
      );
    });
  });
}
