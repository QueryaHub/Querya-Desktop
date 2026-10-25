import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:mysql_client/mysql_protocol.dart';
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
import 'package:querya_desktop/core/database/result_row_string_convert.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';

void main() {
  group('mysqlColumnSchemaType', () {
    test('prefers COLUMN_TYPE so BOOLEAN is tinyint(1)', () {
      expect(
        mysqlColumnSchemaType(dataType: 'tinyint', columnType: 'tinyint(1)'),
        'tinyint(1)',
      );
      expect(
        mysqlColumnSchemaType(dataType: 'bit', columnType: 'bit(8)'),
        'bit(8)',
      );
      expect(
        mysqlColumnSchemaType(dataType: 'json', columnType: 'json'),
        'json',
      );
      expect(
        mysqlColumnSchemaType(dataType: 'blob', columnType: ''),
        'blob',
      );
    });
  });

  group('all_mysql_types display + persist', () {
    test('BOOLEAN tinyint(1) displays true/false and persists TRUE/FALSE', () {
      expect(
        mysqlResultCellToDisplayString('1', schemaDataType: 'tinyint(1)'),
        'true',
      );
      expect(
        mysqlResultCellToDisplayString('0', schemaDataType: 'tinyint(1)'),
        'false',
      );
      expect(
        TableMutationEngine.formatLiteral(
          'true',
          SqlDialect.mysql,
          dataTypeName: 'tinyint(1)',
        ),
        'TRUE',
      );
      expect(
        TableMutationEngine.formatLiteral(
          '0',
          SqlDialect.mysql,
          dataTypeName: 'tinyint(1)',
        ),
        'FALSE',
      );
      expect(TableMutationEngine.isBoolType('tinyint'), isFalse);
      expect(TableMutationEngine.isBoolType('tinyint(1)'), isTrue);
    });

    test('BIT(8) latin1 byte displays as hex and persists X\'..\'', () {
      final bitCol = ResultSetColumn(
        name: 'col_bit',
        type: MySQLColumnType.bitType,
        length: 8,
        charset: 63,
      );
      final raw = latin1.decode(const [0xaa]);
      expect(
        mysqlResultCellToDisplayString(raw, column: bitCol),
        '0xaa',
      );
      expect(
        TableMutationEngine.formatLiteral(
          '0xaa',
          SqlDialect.mysql,
          dataTypeName: 'bit(8)',
        ),
        "X'aa'",
      );
    });

    test('BLOB / BINARY display as hex and persist the same', () {
      const blob = 'Binary BLOB payload';
      expect(
        mysqlResultCellToDisplayString(blob, schemaDataType: 'blob'),
        binaryCellToHexDisplay(blob),
      );
      expect(
        binaryCellToHexDisplay(Uint8List.fromList([0xde, 0xad, 0xbe, 0xef])),
        '0xdeadbeef',
      );
      expect(
        TableMutationEngine.formatLiteral(
          '0xdeadbeef',
          SqlDialect.mysql,
          dataTypeName: 'binary(16)',
        ),
        "X'deadbeef'",
      );
      expect(
        TableMutationEngine.formatLiteral(
          r'\xcafebabe',
          SqlDialect.mysql,
          dataTypeName: 'varbinary(64)',
        ),
        "X'cafebabe'",
      );
    });

    test('JSON stays quoted text', () {
      const json = '{"name":"Querya MySQL","version":"8.4"}';
      expect(
        mysqlResultCellToDisplayString(json, schemaDataType: 'json'),
        json,
      );
      expect(
        TableMutationEngine.formatLiteral(
          json,
          SqlDialect.mysql,
          dataTypeName: 'json',
        ),
        "'$json'",
      );
    });

    test('TINYINT(1) driver column displays as boolean without schema', () {
      final col = ResultSetColumn(
        name: 'col_boolean',
        type: MySQLColumnType.tinyType,
        length: 1,
      );
      expect(mysqlResultCellToDisplayString('1', column: col), 'true');
      expect(mysqlResultCellToDisplayString('0', column: col), 'false');
    });

    test('deduplicates identical strings via StringInternPool', () {
      final pool = StringInternPool();
      final str1 = String.fromCharCodes('intern_test'.codeUnits);
      final str2 = String.fromCharCodes('intern_test'.codeUnits);
      expect(identical(str1, str2), isFalse);

      final res1 = mysqlResultCellToDisplayString(str1, pool: pool);
      final res2 = mysqlResultCellToDisplayString(str2, pool: pool);
      expect(identical(res1, res2), isTrue);
    });
  });

  group('mysqlColumnHoldsRawBytes', () {
    const binary = mysqlCharsetBinary;
    const utf8mb4 = 255;

    test('numbers, dates, JSON, ENUM and SET are text even with charset 63',
        () {
      // The server reports charset 63 for every non-string column; read as
      // bytes, an INT 10 showed as 0x3130 in the grid.
      for (final type in [
        mysqlColumnTypeTiny,
        mysqlColumnTypeShort,
        mysqlColumnTypeLong,
        mysqlColumnTypeLongLong,
        mysqlColumnTypeInt24,
        mysqlColumnTypeNewDecimal,
        mysqlColumnTypeFloat,
        mysqlColumnTypeDouble,
        mysqlColumnTypeDate,
        mysqlColumnTypeTime,
        mysqlColumnTypeDateTime,
        mysqlColumnTypeTimestamp,
        mysqlColumnTypeYear,
        0xf5, // JSON
        mysqlColumnTypeEnum,
        mysqlColumnTypeSet,
      ]) {
        expect(
          mysqlColumnHoldsRawBytes(columnType: type, charset: binary),
          isFalse,
          reason: 'type 0x${type.toRadixString(16)}',
        );
      }
    });

    test('BINARY, VARBINARY and BLOB (charset 63) are bytes', () {
      for (final type in [
        mysqlColumnTypeString,
        mysqlColumnTypeVarString,
        mysqlColumnTypeVarChar,
        mysqlColumnTypeTinyBlob,
        mysqlColumnTypeBlob,
        mysqlColumnTypeMediumBlob,
        mysqlColumnTypeLongBlob,
      ]) {
        expect(
          mysqlColumnHoldsRawBytes(columnType: type, charset: binary),
          isTrue,
          reason: 'type 0x${type.toRadixString(16)}',
        );
      }
    });

    test('CHAR, VARCHAR and TEXT with a text charset are text', () {
      for (final type in [
        mysqlColumnTypeString,
        mysqlColumnTypeVarString,
        mysqlColumnTypeBlob, // TEXT is a BLOB type
        mysqlColumnTypeMediumBlob,
        mysqlColumnTypeLongBlob,
      ]) {
        expect(
          mysqlColumnHoldsRawBytes(columnType: type, charset: utf8mb4),
          isFalse,
          reason: 'type 0x${type.toRadixString(16)}',
        );
      }
    });

    test('BIT and GEOMETRY are always bytes', () {
      expect(
        mysqlColumnHoldsRawBytes(
            columnType: mysqlColumnTypeBit, charset: binary),
        isTrue,
      );
      expect(
        mysqlColumnHoldsRawBytes(
            columnType: mysqlColumnTypeGeometry, charset: binary),
        isTrue,
      );
    });
  });
}
