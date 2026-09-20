import 'package:querya_desktop/core/database/sqlite_connection.dart';
import 'package:querya_desktop/core/database/table_schema_meta.dart';

/// Implicit SQLite `rowid` used as the Table Browser PK when none is declared.
const kSqliteImplicitRowid = 'rowid';

/// Synthetic column so INSERT omits `rowid` and DML types it as INTEGER.
const sqliteImplicitRowidColumn = TableColumnMeta(
  name: kSqliteImplicitRowid,
  dataType: 'INTEGER',
  isNullable: false,
  isPrimaryKey: true,
  primaryKeyPosition: 1,
  omitOnInsert: true,
  hasServerDefault: true,
);

/// PK columns for Table Browser DML.
///
/// Declared PRIMARY KEY wins. Ordinary tables with no PK use implicit `rowid`.
/// `WITHOUT ROWID` tables always declare a PK, so they never hit this fallback.
/// Views have no `rowid` and stay read-only.
List<String> sqliteTableBrowserPrimaryKeys({
  required List<String> declaredPrimaryKeys,
  required bool isView,
}) {
  if (isView) return const [];
  if (declaredPrimaryKeys.isNotEmpty) {
    return List<String>.from(declaredPrimaryKeys);
  }
  return const [kSqliteImplicitRowid];
}

/// True when browse SELECT must project `rowid` (it is not in `SELECT *`).
bool sqliteBrowseNeedsRowidColumn({
  required List<String> primaryKeys,
  required bool isView,
}) {
  if (isView) return false;
  return primaryKeys.length == 1 && primaryKeys.first == kSqliteImplicitRowid;
}

/// Columns for Table Browser `ORDER BY`.
///
/// Declared PK first. Ordinary tables with no PK use implicit `rowid`.
/// Views omit `ORDER BY` (no PK, no `rowid`).
List<String> sqliteBrowseOrderColumns({
  required List<String> primaryKeys,
  required bool isView,
}) {
  if (primaryKeys.isNotEmpty) return List<String>.from(primaryKeys);
  if (!isView) return const [kSqliteImplicitRowid];
  return const [];
}

/// Browse SELECT for Table Browser. PK / `rowid` keep LIMIT/OFFSET stable.
///
/// Implicit-`rowid` tables project `"rowid", *` so DML WHERE can address the row.
String sqliteBrowseDataSql({
  required String qualifiedFrom,
  required List<String> primaryKeys,
  required bool isView,
  required int limit,
  required int offset,
}) {
  final orderCols = sqliteBrowseOrderColumns(
    primaryKeys: primaryKeys,
    isView: isView,
  );
  final pks = sqliteTableBrowserPrimaryKeys(
    declaredPrimaryKeys: primaryKeys,
    isView: isView,
  );
  final select = sqliteBrowseNeedsRowidColumn(primaryKeys: pks, isView: isView)
      ? '${SqliteConnection.quoteIdentifier(kSqliteImplicitRowid)}, *'
      : '*';
  final order = orderCols.isEmpty
      ? ''
      : ' ORDER BY ${orderCols.map(SqliteConnection.quoteIdentifier).join(', ')}';
  return 'SELECT $select FROM $qualifiedFrom$order LIMIT $limit OFFSET $offset';
}
