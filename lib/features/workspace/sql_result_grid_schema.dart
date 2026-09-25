import 'package:querya_desktop/core/database/table_schema_meta.dart';
import 'package:querya_desktop/features/sqlite/sqlite_table_utils.dart';
import 'package:querya_desktop/features/workspace/table_view_staging.dart';

/// Schema facts the SQL result grid needs to make a single-table SELECT
/// editable, mirroring what Table Browser derives from `getTableSchema`.
class SqlResultGridSchema {
  const SqlResultGridSchema({
    this.primaryKeys = const [],
    this.columnDataTypes,
    this.columnMeta,
    this.schemaError,
    this.needsRowidColumn = false,
  });

  /// No schema was looked up (not a simple single-table SELECT).
  static const none = SqlResultGridSchema();

  /// Builds the schema from a [loadTableViewSchema] outcome.
  ///
  /// With [sqliteImplicitRowid], a table without a declared PRIMARY KEY is keyed
  /// by its implicit `rowid` (as in Table Browser); Save then needs `rowid` to be
  /// one of the SELECTed columns.
  factory SqlResultGridSchema.fromLoad(
    TableViewSchemaLoad loaded, {
    bool sqliteImplicitRowid = false,
  }) {
    final schema = loaded.schema;
    if (schema == null) {
      return SqlResultGridSchema(schemaError: loaded.error);
    }

    var primaryKeys = List<String>.from(schema.primaryKeys);
    final types = columnDataTypesFromSchema(schema);
    final meta = columnMetaFromSchema(schema);

    var needsRowid = false;
    if (sqliteImplicitRowid) {
      primaryKeys = sqliteTableBrowserPrimaryKeys(
        declaredPrimaryKeys: primaryKeys,
        isView: false,
      );
      needsRowid = sqliteBrowseNeedsRowidColumn(
        primaryKeys: primaryKeys,
        isView: false,
      );
      if (needsRowid && !meta.containsKey(kSqliteImplicitRowid)) {
        types[kSqliteImplicitRowid] = sqliteImplicitRowidColumn.dataType;
        meta[kSqliteImplicitRowid] = sqliteImplicitRowidColumn;
      }
    }

    return SqlResultGridSchema(
      primaryKeys: primaryKeys,
      columnDataTypes: types,
      columnMeta: meta,
      needsRowidColumn: needsRowid,
    );
  }

  final List<String> primaryKeys;
  final Map<String, String>? columnDataTypes;
  final Map<String, TableColumnMeta>? columnMeta;

  /// `getTableSchema` failure, kept apart from a genuine "no primary key".
  final Object? schemaError;

  /// SQLite table keyed only by implicit `rowid`.
  final bool needsRowidColumn;

  /// Why Save is off, appended to the result status line. Null when nothing
  /// needs saying (editable, or not a plain table SELECT).
  String? editHint(List<String> resultColumns) {
    final error = schemaError;
    if (error != null) {
      return 'Cannot edit: schema unavailable. $error. Run the query again to retry.';
    }
    if (needsRowidColumn && !resultColumns.contains(kSqliteImplicitRowid)) {
      return 'To edit rows, include rowid in the SELECT (this table has no primary key).';
    }
    return null;
  }
}

/// Appends [hint] to [status] as a second sentence.
String withEditHint(String status, String? hint) =>
    hint == null ? status : '$status $hint';
