import 'package:flutter_test/flutter_test.dart';
import 'package:querya_desktop/features/main_screen/grid_data_type_validator.dart';

void main() {
  group('GridDataTypeValidator', () {
    test('validates integer types', () {
      expect(GridDataTypeValidator.validate('123', dataTypeName: 'integer'), isNull);
      expect(GridDataTypeValidator.validate('-456', dataTypeName: 'int4'), isNull);
      expect(GridDataTypeValidator.validate('0', dataTypeName: 'bigint'), isNull);
      expect(GridDataTypeValidator.validate('abc', dataTypeName: 'int'), isNotNull);
      expect(GridDataTypeValidator.validate('12.34', dataTypeName: 'int'), isNotNull);
    });

    test('validates numeric / float / decimal types', () {
      expect(GridDataTypeValidator.validate('123.45', dataTypeName: 'numeric'), isNull);
      expect(GridDataTypeValidator.validate('-0.99', dataTypeName: 'float8'), isNull);
      expect(GridDataTypeValidator.validate('100', dataTypeName: 'decimal'), isNull);
      expect(GridDataTypeValidator.validate('xyz', dataTypeName: 'double'), isNotNull);
    });

    test('validates boolean types', () {
      expect(GridDataTypeValidator.validate('true', dataTypeName: 'boolean'), isNull);
      expect(GridDataTypeValidator.validate('false', dataTypeName: 'bool'), isNull);
      expect(GridDataTypeValidator.validate('1', dataTypeName: 'bool'), isNull);
      expect(GridDataTypeValidator.validate('0', dataTypeName: 'bool'), isNull);
      expect(GridDataTypeValidator.validate('yes', dataTypeName: 'bool'), isNotNull);
    });

    test('validates UUID types', () {
      expect(
        GridDataTypeValidator.validate(
          'a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11',
          dataTypeName: 'uuid',
        ),
        isNull,
      );
      expect(
        GridDataTypeValidator.validate('not-a-uuid', dataTypeName: 'uuid'),
        isNotNull,
      );
    });

    test('validates JSON types', () {
      expect(
        GridDataTypeValidator.validate('{"key": "value"}', dataTypeName: 'json'),
        isNull,
      );
      expect(
        GridDataTypeValidator.validate('[1, 2, 3]', dataTypeName: 'jsonb'),
        isNull,
      );
      expect(
        GridDataTypeValidator.validate('{invalid-json}', dataTypeName: 'json'),
        isNotNull,
      );
      expect(
        GridDataTypeValidator.validate('plain text', dataTypeName: 'json'),
        isNotNull,
      );
    });

    test('validates date and timestamp types', () {
      expect(GridDataTypeValidator.validate('2026-08-25', dataTypeName: 'date'), isNull);
      expect(GridDataTypeValidator.validate('25-08-2026', dataTypeName: 'date'), isNotNull);
      expect(
        GridDataTypeValidator.validate(
          '2026-08-25 14:30:00',
          dataTypeName: 'timestamp',
        ),
        isNull,
      );
      expect(
        GridDataTypeValidator.validate('invalid date', dataTypeName: 'timestamp'),
        isNotNull,
      );
    });

    test('allows empty and NULL values regardless of type', () {
      expect(GridDataTypeValidator.validate('', dataTypeName: 'int'), isNull);
      expect(GridDataTypeValidator.validate('NULL', dataTypeName: 'uuid'), isNull);
      expect(GridDataTypeValidator.validate('null', dataTypeName: 'json'), isNull);
    });
  });
}
