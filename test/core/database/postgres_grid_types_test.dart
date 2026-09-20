import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:postgres/postgres.dart';
import 'package:querya_desktop/core/database/postgres_result_cells.dart';
import 'package:querya_desktop/core/database/table_mutation_engine.dart';
import 'package:querya_desktop/features/postgresql/postgres_result_utils.dart';
import 'package:querya_desktop/features/workspace/grid_data_type_validator.dart';

void main() {
  group('postgresColumnSchemaType', () {
    test('ARRAY uses udt_name element plus []', () {
      expect(
        postgresColumnSchemaType(dataType: 'ARRAY', udtName: '_int4'),
        'int4[]',
      );
      expect(
        postgresColumnSchemaType(dataType: 'ARRAY', udtName: '_jsonb'),
        'jsonb[]',
      );
    });

    test('USER-DEFINED uses udt_name (enum / domain)', () {
      expect(
        postgresColumnSchemaType(
          dataType: 'USER-DEFINED',
          udtName: 'user_role_enum',
        ),
        'user_role_enum',
      );
    });

    test('prefers udt_name over data_type', () {
      expect(
        postgresColumnSchemaType(
          dataType: 'timestamp with time zone',
          udtName: 'timestamptz',
        ),
        'timestamptz',
      );
      expect(
        postgresColumnSchemaType(dataType: 'bytea', udtName: 'bytea'),
        'bytea',
      );
      expect(
        postgresColumnSchemaType(dataType: 'jsonb', udtName: 'jsonb'),
        'jsonb',
      );
    });
  });

  group('all_types display + persist', () {
    test('timestamptz DateTime displays ISO and persists quoted', () {
      final dt = DateTime.utc(2026, 8, 26, 10, 30);
      expect(
        postgresResultCellToDisplayString(
          dt,
          typeOid: Type.timestampTz.oid,
          dataTypeName: 'timestamptz',
        ),
        dt.toIso8601String(),
      );
      expect(
        TableMutationEngine.formatLiteral(
          dt.toIso8601String(),
          SqlDialect.postgres,
          dataTypeName: 'timestamptz',
        ),
        "'${dt.toIso8601String()}'",
      );
    });

    test('bytea displays \\x hex and persists as bytea literal', () {
      expect(
        postgresResultCellToDisplayString(
          Uint8List.fromList(const [0xde, 0xad, 0xbe, 0xef]),
          dataTypeName: 'bytea',
        ),
        r'\xdeadbeef',
      );
      expect(
        TableMutationEngine.formatLiteral(
          r'\xdeadbeef',
          SqlDialect.postgres,
          dataTypeName: 'bytea',
        ),
        r"'\xdeadbeef'::bytea",
      );
    });

    test('jsonb Map displays JSON text and persists quoted', () {
      const decoded = {
        'id': 42,
        'user': {'email': 'alice@querya.dev'},
      };
      final shown = postgresResultCellToDisplayString(
        decoded,
        typeOid: Type.jsonb.oid,
        dataTypeName: 'jsonb',
      );
      expect(json.decode(shown), decoded);
      expect(
        TableMutationEngine.formatLiteral(
          shown,
          SqlDialect.postgres,
          dataTypeName: 'jsonb',
        ),
        "'$shown'",
      );
    });

    test('enum stays a quoted label', () {
      expect(
        postgresResultCellToDisplayString(
          'admin',
          dataTypeName: 'user_role_enum',
        ),
        'admin',
      );
      expect(
        TableMutationEngine.formatLiteral(
          'admin',
          SqlDialect.postgres,
          dataTypeName: 'user_role_enum',
        ),
        "'admin'",
      );
    });

    test('int[] displays PG array text and persists quoted', () {
      expect(
        postgresResultCellToDisplayString(
          [1, 2, 3, 42, 999],
          dataTypeName: 'int4[]',
        ),
        '{1,2,3,42,999}',
      );
      expect(
        TableMutationEngine.formatLiteral(
          '{1,2,3,42,999}',
          SqlDialect.postgres,
          dataTypeName: 'int4[]',
        ),
        "'{1,2,3,42,999}'",
      );
      expect(
        GridDataTypeValidator.validate('{1,2,3}', dataTypeName: 'int4[]'),
        isNull,
      );
    });
  });

  group('convertPostgresResultRowsToStrings', () {
    test('maps timestamptz, bytea, jsonb, array — not Object.toString', () {
      final dt = DateTime.utc(2026, 1, 1, 0, 0, 0);
      final out = convertPostgresResultRowsToStrings(
        PostgresResultConvertJob(
          rowValues: [
            [
              dt,
              Uint8List.fromList(const [0xca, 0xfe]),
              {'a': true},
              [10, 20],
              null,
            ],
          ],
          columnDataTypes: const [
            'timestamptz',
            'bytea',
            'jsonb',
            'int4[]',
            'text',
          ],
        ),
      );
      expect(out.single, [
        dt.toIso8601String(),
        r'\xcafe',
        '{"a":true}',
        '{10,20}',
        'NULL',
      ]);
    });
  });
}
