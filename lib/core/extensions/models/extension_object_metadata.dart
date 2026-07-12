/// Represents a column in a database object inspected by an extension driver.
class ExtensionObjectColumn {
  const ExtensionObjectColumn({
    required this.name,
    required this.dataType,
    this.isNullable = true,
    this.defaultValue,
    this.comment,
  });

  final String name;
  final String dataType;
  final bool isNullable;
  final String? defaultValue;
  final String? comment;

  factory ExtensionObjectColumn.fromRpc(Object? raw) {
    if (raw is! Map) {
      return const ExtensionObjectColumn(name: '', dataType: '');
    }
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);
    return ExtensionObjectColumn(
      name: '${map['name'] ?? ''}'.trim(),
      dataType:
          '${map['dataType'] ?? map['data_type'] ?? map['type'] ?? ''}'.trim(),
      isNullable: map['isNullable'] == false ||
              map['is_nullable'] == false ||
              map['nullable'] == false
          ? false
          : true,
      defaultValue: map['defaultValue']?.toString() ??
          map['default_value']?.toString(),
      comment: map['comment']?.toString(),
    );
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'dataType': dataType,
        'isNullable': isNullable,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (comment != null) 'comment': comment,
      };
}

/// DDL and structural metadata returned by `db.getObjectDDL` / `db.getObjectMetadata`.
class ExtensionObjectMetadata {
  const ExtensionObjectMetadata({
    this.nodeId = '',
    this.nodeType = '',
    this.ddl,
    this.columns = const [],
    this.properties = const {},
  });

  final String nodeId;
  final String nodeType;

  /// The SQL creation statement (`CREATE TABLE ...`, `CREATE FUNCTION ...`).
  final String? ddl;

  /// Structural columns if `nodeType` is a table or view.
  final List<ExtensionObjectColumn> columns;

  /// Additional key-value properties (e.g., engine, row count, comment).
  final Map<String, Object?> properties;

  factory ExtensionObjectMetadata.fromRpc(Object? raw) {
    if (raw is! Map) return const ExtensionObjectMetadata();
    final map = raw is Map<String, dynamic>
        ? raw
        : Map<String, dynamic>.from(raw);

    final cols = <ExtensionObjectColumn>[];
    final rawCols = map['columns'];
    if (rawCols is List) {
      for (final col in rawCols) {
        cols.add(ExtensionObjectColumn.fromRpc(col));
      }
    }

    final props = <String, Object?>{};
    final rawProps = map['properties'];
    if (rawProps is Map) {
      rawProps.forEach((k, v) {
        if (v != null) props['$k'] = v;
      });
    }

    return ExtensionObjectMetadata(
      nodeId: '${map['nodeId'] ?? map['node_id'] ?? ''}'.trim(),
      nodeType: '${map['nodeType'] ?? map['node_type'] ?? ''}'.trim(),
      ddl: map['ddl']?.toString() ?? map['sql']?.toString(),
      columns: cols,
      properties: props,
    );
  }

  Map<String, Object?> toJson() => {
        'nodeId': nodeId,
        'nodeType': nodeType,
        if (ddl != null) 'ddl': ddl,
        'columns': columns.map((c) => c.toJson()).toList(),
        'properties': properties,
      };
}
