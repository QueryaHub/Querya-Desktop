import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/sqlite/sqlite_result_utils.dart';

void main() {
  group('sqliteResultCellToDisplayString', () {
    test('BLOB bytes display as X\'hex\'', () {
      expect(
        sqliteResultCellToDisplayString(
          Uint8List.fromList(const [0xde, 0xad, 0xbe, 0xef]),
        ),
        "X'deadbeef'",
      );
      expect(
        sqliteResultCellToDisplayString(
          const [0x00, 0x00, 0x00, 0x00],
          dataTypeName: 'BLOB',
        ),
        "X'00000000'",
      );
    });

    test('TEXT stays the string, including leading zeros', () {
      expect(
        sqliteResultCellToDisplayString('00123', dataTypeName: 'TEXT'),
        '00123',
      );
      expect(sqliteResultCellToDisplayString(null), 'NULL');
    });
  });

  group('all_sqlite_types persist', () {
    test('BLOB hex persists as X\'..\'', () {
      expect(
        TableMutationEngine.formatLiteral(
          "X'deadbeefcafe0102030405'",
          SqlDialect.sqlite,
          dataTypeName: 'BLOB',
        ),
        "X'deadbeefcafe0102030405'",
      );
    });

    test('TEXT 00123 stays a quoted string, not an integer', () {
      expect(
        TableMutationEngine.formatLiteral(
          '00123',
          SqlDialect.sqlite,
          dataTypeName: 'TEXT',
        ),
        "'00123'",
      );
      expect(
        TableMutationEngine.formatLiteral(
          '123',
          SqlDialect.sqlite,
          dataTypeName: 'text',
        ),
        "'123'",
      );
    });
  });

  group('convertSqliteResultRowsToStrings', () {
    test('maps blob bytes to hex, not List.toString', () {
      final out = convertSqliteResultRowsToStrings(
        SqliteResultConvertJob(
          rowValues: [
            [
              'ok',
              Uint8List.fromList(const [0xca, 0xfe]),
              null,
            ],
          ],
        ),
      );
      expect(out.single, ['ok', "X'cafe'", 'NULL']);
    });
  });
}
