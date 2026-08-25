import 'dart:convert';

/// Helper utility for validating cell values against SQL data types.
abstract final class GridDataTypeValidator {
  static final _uuidRegex = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );
  static final _intRegex = RegExp(r'^-?\d+$');
  static final _numRegex = RegExp(r'^-?\d+(\.\d+)?$');
  static final _dateRegex = RegExp(r'^\d{4}-\d{2}-\d{2}$');
  static final _timestampRegex = RegExp(
    r'^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}(:\d{2})?)?$',
  );

  /// Validates [value] against the column's [dataTypeName].
  /// Returns `null` if valid (or type is unknown), or an error description string if invalid.
  static String? validate(String value, {String? dataTypeName}) {
    if (value.isEmpty || value == 'NULL' || value == 'null') {
      return null;
    }
    if (dataTypeName == null || dataTypeName.isEmpty) {
      return null;
    }

    final type = dataTypeName.toLowerCase().trim();

    // Integer types
    if (type.contains('int') || type == 'serial' || type == 'bigserial') {
      if (!_intRegex.hasMatch(value.trim())) {
        return 'Expected valid integer';
      }
      return null;
    }

    // Floating / Decimal / Numeric types
    if (type.contains('num') ||
        type.contains('decimal') ||
        type.contains('float') ||
        type.contains('double') ||
        type == 'real') {
      if (!_numRegex.hasMatch(value.trim())) {
        return 'Expected valid number';
      }
      return null;
    }

    // Boolean types
    if (type == 'bool' || type == 'boolean') {
      final lower = value.toLowerCase().trim();
      if (lower != 'true' &&
          lower != 'false' &&
          lower != '1' &&
          lower != '0' &&
          lower != 't' &&
          lower != 'f') {
        return 'Expected boolean (true/false/1/0)';
      }
      return null;
    }

    // UUID
    if (type == 'uuid') {
      if (!_uuidRegex.hasMatch(value.trim())) {
        return 'Expected valid UUID (e.g. 123e4567-e89b-12d3-a456-426614174000)';
      }
      return null;
    }

    // JSON / JSONB
    if (type.contains('json')) {
      final trimmed = value.trim();
      if (!((trimmed.startsWith('{') && trimmed.endsWith('}')) ||
          (trimmed.startsWith('[') && trimmed.endsWith(']')))) {
        return 'Expected valid JSON object or array';
      }
      try {
        jsonDecode(trimmed);
      } catch (e) {
        return 'Malformed JSON: $e';
      }
      return null;
    }

    // Date
    if (type == 'date') {
      if (!_dateRegex.hasMatch(value.trim())) {
        return 'Expected date in YYYY-MM-DD format';
      }
      return null;
    }

    // Timestamp / DateTime
    if (type.contains('timestamp') ||
        type.contains('datetime') ||
        type == 'timestamptz') {
      if (!_timestampRegex.hasMatch(value.trim())) {
        return 'Expected timestamp (YYYY-MM-DD HH:MM:SS)';
      }
      return null;
    }

    return null;
  }
}
