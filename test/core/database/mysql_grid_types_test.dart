import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mysql_client/mysql_client.dart';
import 'package:mysql_client/mysql_protocol.dart';
import 'package:querya_desktop/core/database/mysql_result_cells.dart';
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
  });
}
