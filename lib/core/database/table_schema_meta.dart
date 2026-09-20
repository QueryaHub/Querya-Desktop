/// Column schema metadata.
class TableColumnMeta {
  const TableColumnMeta({
    required this.name,
    required this.dataType,
    this.isNullable = true,
    this.isPrimaryKey = false,
    this.primaryKeyPosition,
    this.defaultValue,
    this.omitOnInsert = false,
    this.hasServerDefault = false,
  });

  final String name;
  final String dataType;
  final bool isNullable;
  final bool isPrimaryKey;
  final int? primaryKeyPosition;
  final String? defaultValue;

  /// Never send on INSERT (GENERATED ALWAYS, identity always, AUTO_INCREMENT).
  final bool omitOnInsert;

  /// Empty INSERT cells should omit the column so DEFAULT / serial applies.
  final bool hasServerDefault;

  Map<String, Object?> toJson() => {
        'name': name,
        'dataType': dataType,
        'isNullable': isNullable,
        'isPrimaryKey': isPrimaryKey,
        'primaryKeyPosition': primaryKeyPosition,
        'defaultValue': defaultValue,
        'omitOnInsert': omitOnInsert,
        'hasServerDefault': hasServerDefault,
      };

  factory TableColumnMeta.fromJson(Map<String, Object?> json) =>
      TableColumnMeta(
        name: json['name'] as String,
        dataType: json['dataType'] as String,
        isNullable: json['isNullable'] as bool? ?? true,
        isPrimaryKey: json['isPrimaryKey'] as bool? ?? false,
        primaryKeyPosition: json['primaryKeyPosition'] as int?,
        defaultValue: json['defaultValue'] as String?,
        omitOnInsert: json['omitOnInsert'] as bool? ?? false,
        hasServerDefault: json['hasServerDefault'] as bool? ?? false,
      );
}

/// Table schema metadata containing column descriptions and primary keys.
class TableSchemaMeta {
  const TableSchemaMeta({
    required this.tableName,
    this.schema,
    this.columns = const [],
    this.primaryKeys = const [],
  });

  final String tableName;
  final String? schema;
  final List<TableColumnMeta> columns;
  final List<String> primaryKeys;

  bool get hasPrimaryKey => primaryKeys.isNotEmpty;

  TableColumnMeta? getColumn(String name) {
    for (final col in columns) {
      if (col.name == name) return col;
    }
    return null;
  }

  Map<String, Object?> toJson() => {
        'tableName': tableName,
        'schema': schema,
        'columns': columns.map((c) => c.toJson()).toList(),
        'primaryKeys': primaryKeys,
      };

  factory TableSchemaMeta.fromJson(Map<String, Object?> json) =>
      TableSchemaMeta(
        tableName: json['tableName'] as String,
        schema: json['schema'] as String?,
        columns: (json['columns'] as List<dynamic>? ?? const [])
            .map((c) => TableColumnMeta.fromJson(c as Map<String, Object?>))
            .toList(),
        primaryKeys: (json['primaryKeys'] as List<dynamic>? ?? const [])
            .map((e) => e.toString())
            .toList(),
      );
}
